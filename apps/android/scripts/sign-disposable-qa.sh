#!/usr/bin/env bash
set -euo pipefail
apk=${1:?Expected APK path}
test -s "$apk"
tools_dir=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$apk" "$work/unsigned-input.apk"
export QA_SIGN_PASSWORD=$(openssl rand -hex 24)
echo "QA signature stage 1: generate one-time public-source signing key"
keytool -genkeypair -storetype PKCS12 -keystore "$work/qa.p12" -alias temporaryqa -keyalg RSA -keysize 3072 -validity 2 -storepass "$QA_SIGN_PASSWORD" -keypass "$QA_SIGN_PASSWORD" -dname 'CN=Temporary Source QA, O=Elementera Coast Source' -noprompt
echo "QA signature stage 2: sign APK with V1 V2 V3"
"$tools_dir/apksigner" sign --ks "$work/qa.p12" --ks-key-alias temporaryqa --ks-pass env:QA_SIGN_PASSWORD --key-pass env:QA_SIGN_PASSWORD --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false --out "$apk" "$work/unsigned-input.apk"
echo "QA signature stage 3: inspect signatures"
"$tools_dir/apksigner" verify --verbose --min-sdk-version 26 --print-certs "$apk" | tee "$work/verify.txt"
grep -F 'Verified using v1 scheme (JAR signing): true' "$work/verify.txt"
grep -F 'Verified using v2 scheme (APK Signature Scheme v2): true' "$work/verify.txt"
echo "QA signature stage 4: inspect embedded signature files"
unzip -Z1 "$apk" > "$work/files.txt"
grep -E "^META-INF/" "$work/files.txt" || true
grep -Eq '^META-INF/[^/]+\.RSA$' "$work/files.txt"
grep -Eq '^META-INF/[^/]+\.SF$' "$work/files.txt"
echo 'Disposable public-source APK signed with V1/JAR and V2; actual signature files verified.'
