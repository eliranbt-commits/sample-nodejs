#!/usr/bin/env bash
# Write the release version into Chart.yaml, package.json, and GitOps values.
set -euo pipefail

version="${1:?usage: apply-version.sh <x.y.z> <image-repository>}"
repository="${2:?usage: apply-version.sh <x.y.z> <image-repository>}"

root="$(cd "$(dirname "$0")/.." && pwd)"
chart="$root/helm/sample-nodejs/Chart.yaml"
values="$root/helm/sample-nodejs/values-gitops.yaml"
pkg="$root/web-app/package.json"

chart_version="$(sed -n 's/^version: //p' "$chart" | head -n1 | tr -d '"')"
next_chart="$("$root/scripts/next-version.sh" "$chart_version" patch)"

sed -i "s/^version: .*/version: ${next_chart}/" "$chart"
sed -i "s/^appVersion: .*/appVersion: \"${version}\"/" "$chart"
sed -i "s/^  repository: .*/  repository: ${repository}/" "$values"
sed -i "s/^  tag: .*/  tag: \"${version}\"/" "$values"
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"${version}\"/" "$pkg"
