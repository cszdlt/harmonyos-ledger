import { execFileSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

interface SigningMaterial {
  certpath: string;
  storePassword: string;
  keyAlias: string;
  keyPassword: string;
  profile: string;
  signAlg: string;
  storeFile: string;
}

interface SigningConfig {
  name: string;
  type: string;
  material: SigningMaterial;
}

const projectRoot = __dirname;
const signingConfigPath = path.join(projectRoot, 'signing.local.json');

function getCommitCount(): number {
  let output: string;
  try {
    output = execFileSync('git', ['rev-list', '--count', 'HEAD'], {
      cwd: projectRoot,
      encoding: 'utf8'
    }).trim();
  } catch {
    throw new Error('Unable to read Git history for application versioning. Build from a Git checkout with full history.');
  }

  const commitCount = Number(output);
  if (!Number.isSafeInteger(commitCount) || commitCount < 1) {
    throw new Error('Git history returned an invalid commit count for application versioning.');
  }
  return commitCount;
}

function getVersionTag(): string {
  try {
    return execFileSync('git', ['describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*', 'HEAD'], {
      cwd: projectRoot,
      encoding: 'utf8'
    }).trim();
  } catch {
    throw new Error('Unable to read a reachable v* version tag. Build from a Git checkout with a version tag.');
  }
}

function readSigningConfig(): SigningConfig | undefined {
  if (!fs.existsSync(signingConfigPath)) {
    console.warn(`Local signing config not found: ${signingConfigPath}; building without a signing config.`);
    return undefined;
  }

  const config = JSON.parse(fs.readFileSync(signingConfigPath, 'utf8')) as SigningConfig;
  const requiredFields: Array<keyof SigningMaterial> = [
    'certpath', 'storePassword', 'keyAlias', 'keyPassword', 'profile', 'signAlg', 'storeFile'
  ];
  if (!config.name || !config.type || !config.material ||
    requiredFields.some((field) => typeof config.material[field] !== 'string' || config.material[field].length === 0)) {
    throw new Error('Local signing config is missing required signing fields.');
  }
  return config;
}

export default {
  system: appTasks,
  plugins: []
};

hvigor.afterNodeEvaluate((hvigorNode) => {
  const appContext = hvigorNode.getContext(OhosPluginId.OHOS_APP_PLUGIN);
  if (!appContext) {
    return;
  }

  const commitCount = getCommitCount();
  const appJson = appContext.getAppJsonOpt();
  appJson.app.versionCode = commitCount + 1000000;
  appJson.app.versionName = `${getVersionTag().replace(/^v/, '')}.${commitCount}`;
  appContext.setAppJsonOpt(appJson);

  const buildProfile = appContext.getBuildProfileOpt();
  const signingConfig = readSigningConfig();
  if (signingConfig) {
    buildProfile.app.signingConfigs = [signingConfig];
    buildProfile.app.products.forEach((product) => {
      product.signingConfig = signingConfig.name;
    });
  }
  appContext.setBuildProfileOpt(buildProfile);
});
