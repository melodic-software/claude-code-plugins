#!/usr/bin/env bash
# An Expo React Native app with a bottom sheet that has no gesture.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" app package.json
mkdir -p app/components
cat > package.json <<'JSON'
{ "name": "tidelog", "private": true, "main": "expo-router/entry", "dependencies": { "expo": "~52.0.0", "react": "18.3.1", "react-native": "0.76.0", "react-native-gesture-handler": "~2.20.0", "react-native-reanimated": "~3.16.0" } }
JSON
cat > app/components/Sheet.tsx <<'TSX'
import { View, StyleSheet } from "react-native";
import type { ReactNode } from "react";

export function Sheet({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  return <View style={styles.sheet}>{children}</View>;
}

const styles = StyleSheet.create({
  sheet: { position: "absolute", left: 0, right: 0, bottom: 0, padding: 16, borderTopLeftRadius: 16, borderTopRightRadius: 16, backgroundColor: "white" },
});
TSX
