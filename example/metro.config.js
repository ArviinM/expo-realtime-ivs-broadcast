// Learn more https://docs.expo.io/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);

// npm v7+ will install ../node_modules/react and ../node_modules/react-native because of peerDependencies.
// To prevent the incompatible react-native between ./node_modules/react-native and ../node_modules/react-native,
// excludes the one from the parent folder when bundling.
config.resolver.blockList = [
  ...Array.from(config.resolver.blockList ?? []),
  new RegExp(path.resolve('..', 'node_modules', 'react')),
  new RegExp(path.resolve('..', 'node_modules', 'react-native')),
  // Block parent's expo packages to prevent version conflicts
  new RegExp(path.resolve('..', 'node_modules', 'expo') + '(?!-realtime)'),
  new RegExp(path.resolve('..', 'node_modules', 'expo-constants')),
  new RegExp(path.resolve('..', 'node_modules', 'expo-asset')),
  new RegExp(path.resolve('..', 'node_modules', 'expo-file-system')),
  new RegExp(path.resolve('..', 'node_modules', 'expo-font')),
  new RegExp(path.resolve('..', 'node_modules', 'expo-keep-awake')),
  new RegExp(path.resolve('..', 'node_modules', 'expo-modules-core')),
  new RegExp(path.resolve('..', 'node_modules', '@expo')),
];

config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, './node_modules'),
  path.resolve(__dirname, '../node_modules'),
];

config.resolver.extraNodeModules = {
  'expo-realtime-ivs-broadcast': '..',
};

config.watchFolders = [path.resolve(__dirname, '..')];

config.transformer.getTransformOptions = async () => ({
  transform: {
    experimentalImportSupport: false,
    inlineRequires: true,
  },
});

module.exports = config;
