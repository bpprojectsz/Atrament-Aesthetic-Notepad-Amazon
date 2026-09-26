#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== STARTING AMAZON FORK SYNC ==="

# Fetch upstream (the main repo)
git fetch upstream

# Attempt merge without committing
git merge upstream/main --no-commit --no-ff || true

# Protected identity files — never overwritten by upstream.
#
# Category A: Amazon-only files that do not exist in the main repo.
# Category B: files that exist in both repos but must differ here.
PROTECTED=(
  # Category A — Amazon-only
  "app/android/app/src/main/assets/AppstoreAuthenticationKey.pem"
  "app/android/app/src/main/kotlin/com/zdmgold/atrament/AmazonIapHandler.kt"
  "app/lib/platform/amazon_iap_service.dart"
  # Category B — must differ in the fork
  "app/pubspec.yaml"
  "app/android/app/build.gradle"
  "app/android/app/proguard-rules.pro"
  "app/android/app/src/main/AndroidManifest.xml"
  "app/android/app/src/main/kotlin/com/zdmgold/atrament/MainActivity.kt"
  "app/lib/core/services/iap_service.dart"
  "app/lib/core/providers/subscription_provider.dart"
  "app/lib/screens/premium_screen.dart"
  "app/lib/core/services/engagement_service.dart"
  ".github/workflows/build_and_deploy.yml"
)

CONFLICTED=$(git diff --name-only --diff-filter=U)

if [ -n "$CONFLICTED" ]; then
  echo "Conflicts detected. Protecting Amazon identity..."
  for file in $CONFLICTED; do
    IS_PROTECTED=false
    for p in "${PROTECTED[@]}"; do
      if [ "$file" == "$p" ]; then
        IS_PROTECTED=true
        break
      fi
    done
    if $IS_PROTECTED; then
      echo "  -> keep Amazon: $file"
      git checkout --ours "$file"
    else
      echo "  -> accept main: $file"
      git checkout --theirs "$file"
    fi
    git add "$file"
  done
else
  echo "Clean merge."
  # Even on a clean merge, verify no protected file was silently overwritten
  CHANGED=$(git diff --cached --name-only)
  for p in "${PROTECTED[@]}"; do
    if echo "$CHANGED" | grep -qx "$p"; then
      echo "  -> reverting upstream change to protected: $p"
      git checkout HEAD -- "$p"
      git add "$p"
    fi
  done
fi

echo "=== SYNC COMPLETE ==="
echo "Review with: git status --short"
echo "Then: git commit -m 'chore: sync from main' && git push origin main"
