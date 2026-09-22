#!/usr/bin/env bash
# Write the same release version into Chart.yaml, values-gitops.yaml, and package.json if present.
set -euo pipefail

version="${1:?usage: apply-version.sh <x.y.z> <image-repository> <repo-root>}"
repository="${2:?usage: apply-version.sh <x.y.z> <image-repository> <repo-root>}"
repo_root="${3:?usage: apply-version.sh <x.y.z> <image-repository> <repo-root>}"
version="${version//$'\r'/}"
version="${version## }"
version="${version%% }"
repository="${repository//$'\r'/}"

chart="$repo_root/helm/sample-nodejs/Chart.yaml"
values="$repo_root/helm/sample-nodejs/values-gitops.yaml"
pkg="$repo_root/web-app/package.json"

# Same number everywhere: Helm chart version, appVersion, image tag, package.json.
sed -i "s|^version: .*|version: ${version}|" "$chart"
sed -i "s|^appVersion: .*|appVersion: \"${version}\"|" "$chart"
sed -i "s|^  repository: .*|  repository: ${repository}|" "$values"
sed -i "s|^  tag: .*|  tag: \"${version}\"|" "$values"
if [[ -f "$pkg" ]]; then
  sed -i "s|\"version\": \"[^\"]*\"|\"version\": \"${version}\"|" "$pkg"
fi

echo "Pinned chart ${version}, appVersion ${version}, image ${repository}:${version}"
