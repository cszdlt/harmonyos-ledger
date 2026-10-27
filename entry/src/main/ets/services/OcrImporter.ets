import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { OcrLine, OcrRecognitionResult, OcrRecognizedPage } from '../model/OcrModels';

// 超过 4096px 的长图分块识别，相邻切片保留 256px 重叠以避免截断文本。
const MAX_OCR_SLICE_HEIGHT = 4096;
const OCR_SLICE_OVERLAP = 256;

interface OcrImageRecognition {
  lines: OcrLine[];
  rawText: string;
  imageWidth: number;
}

function toOcrText(result: textRecognition.TextRecognitionResult): string {
  const lines: string[] = [];
  result.blocks.forEach((block: textRecognition.TextBlock) => {
    block.lines.forEach((line: textRecognition.TextLine) => {
      lines.push(line.value);
    });
  });
  return lines.join('\n');
}

function toOcrLines(result: textRecognition.TextRecognitionResult, topOffset: number = 0): OcrLine[] {
  const lines: OcrLine[] = [];
  result.blocks.forEach((block: textRecognition.TextBlock) => {
    block.lines.forEach((line: textRecognition.TextLine) => {
      if (line.cornerPoints.length < 4) {
        return;
      }
      let left = line.cornerPoints[0].x;
      let right = line.cornerPoints[0].x;
      let top = line.cornerPoints[0].y;
      let bottom = line.cornerPoints[0].y;
      line.cornerPoints.forEach((point: textRecognition.PixelPoint) => {
        left = Math.min(left, point.x);
        right = Math.max(right, point.x);
        top = Math.min(top, point.y);
        bottom = Math.max(bottom, point.y);
      });
      lines.push({
        text: line.value,
        left: left,
        top: top + topOffset,
        right: right,
        bottom: bottom + topOffset,
        centerY: (top + bottom) / 2 + topOffset,
        height: Math.max(1, bottom - top)
      });
    });
  });
  return lines;
}

function sameOverlappingOcrLine(first: OcrLine, second: OcrLine): boolean {
  const firstText = first.text.replace(/\s/g, '').toLowerCase();
  if (firstText.length === 0 || firstText !== second.text.replace(/\s/g, '').toLowerCase()) {
    return false;
  }
  const horizontalOverlap = Math.max(0, Math.min(first.right, second.right) - Math.max(first.left, second.left));
  const narrowerWidth = Math.max(1, Math.min(first.right - first.left, second.right - second.left));
  if (horizontalOverlap / narrowerWidth < 0.5) {
    return false;
  }
  return Math.abs(first.centerY - second.centerY) <= Math.max(8, Math.max(first.height, second.height) * 0.6);
}

function appendOcrSlice(
  mergedLines: OcrLine[],
  sliceLines: OcrLine[],
  overlapTop: number,
  overlapBottom: number
): void {
  const previousLines = mergedLines.slice();
  sliceLines.forEach((line: OcrLine) => {
    const isDuplicate = line.centerY >= overlapTop && line.centerY <= overlapBottom &&
      previousLines.some((previous: OcrLine) => previous.centerY >= overlapTop &&
        previous.centerY <= overlapBottom && sameOverlappingOcrLine(previous, line));
    if (!isDuplicate) {
      mergedLines.push(line);
    }
  });
}

async function recognizeImage(imageSource: image.ImageSource): Promise<OcrImageRecognition> {
  const imageInfo = await imageSource.getImageInfo();
  const imageWidth = imageInfo.size.width;
  const imageHeight = imageInfo.size.height;
  if (imageHeight <= MAX_OCR_SLICE_HEIGHT) {
    const pixelMap = await imageSource.createPixelMap();
    try {
      const recognition = await textRecognition.recognizeText({ pixelMap: pixelMap });
      return { lines: toOcrLines(recognition), rawText: toOcrText(recognition), imageWidth: imageWidth };
    } finally {
      await pixelMap.release();
    }
  }

  const sliceCount = Math.ceil((imageHeight - OCR_SLICE_OVERLAP) /
    (MAX_OCR_SLICE_HEIGHT - OCR_SLICE_OVERLAP));
  const sliceHeight = Math.ceil((imageHeight + OCR_SLICE_OVERLAP * (sliceCount - 1)) / sliceCount);
  const sliceStride = sliceHeight - OCR_SLICE_OVERLAP;
  const mergedLines: OcrLine[] = [];
  let previousSliceBottom = 0;
  for (let sliceIndex = 0; sliceIndex < sliceCount; sliceIndex++) {
    const sliceTop = sliceIndex * sliceStride;
    const currentSliceHeight = Math.min(sliceHeight, imageHeight - sliceTop);
    const pixelMap = await imageSource.createPixelMap({
      desiredRegion: {
        x: 0,
        y: sliceTop,
        size: { width: imageWidth, height: currentSliceHeight }
      }
    });
    try {
      const recognition = await textRecognition.recognizeText({ pixelMap: pixelMap });
      appendOcrSlice(
        mergedLines,
        toOcrLines(recognition, sliceTop),
        sliceTop,
        previousSliceBottom
      );
    } finally {
      await pixelMap.release();
    }
    previousSliceBottom = sliceTop + currentSliceHeight;
  }
  return {
    lines: mergedLines,
    rawText: mergedLines.map((line: OcrLine) => line.text).join('\n'),
    imageWidth: imageWidth
  };
}

async function imageCaptureTime(file: fileIo.File): Promise<number | undefined> {
  try {
    const stat = await fileIo.stat(file.fd);
    return stat.mtime > 0 ? stat.mtime * 1000 : undefined;
  } catch (_error) {
    return undefined;
  }
}

export class OcrImporter {
  static async chooseAndRecognize(context: common.UIAbilityContext, maxSelectNumber: number = 20): Promise<OcrRecognitionResult> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxSelectNumber;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const selection = await picker.select(options);
    if (selection.photoUris.length === 0) {
      return { pages: [] };
    }
    return OcrImporter.recognizeUris(selection.photoUris);
  }

  static async recognizeUris(uris: string[]): Promise<OcrRecognitionResult> {
    if (uris.length === 0) {
      return { pages: [] };
    }

    const initialized = await textRecognition.init();
    if (!initialized) {
      throw new Error('系统文字识别初始化失败，请稍后重试或手动记账');
    }

    const pages: OcrRecognizedPage[] = [];
    let succeeded = 0;
    let lastError = '';
    try {
      for (let imageIndex = 0; imageIndex < uris.length; imageIndex++) {
        const uri = uris[imageIndex];
        let file: fileIo.File | undefined = undefined;
        let imageSource: image.ImageSource | undefined = undefined;
        let capturedAt: number | undefined = undefined;
        try {
          file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
          capturedAt = await imageCaptureTime(file);
          imageSource = image.createImageSource(file.fd);
          const recognition = await recognizeImage(imageSource);
          pages.push({
            pageNumber: imageIndex + 1,
            lines: recognition.lines,
            rawText: recognition.rawText,
            captureTime: capturedAt,
            imageWidth: recognition.imageWidth
          });
          succeeded++;
        } catch (error) {
          const businessError = error as BusinessError;
          lastError = businessError.message;
          pages.push({
            pageNumber: imageIndex + 1,
            lines: [],
            rawText: '识别失败：' + lastError,
            captureTime: capturedAt
          });
        } finally {
          try {
            if (imageSource !== undefined) {
              await imageSource.release();
            }
          } finally {
            if (file !== undefined) {
              fileIo.closeSync(file);
            }
          }
        }
      }
    } finally {
      await textRecognition.release();
    }

    if (succeeded === 0 && lastError.length > 0) {
      throw new Error('图片识别失败：' + lastError);
    }
    return { pages: pages };
  }
}
