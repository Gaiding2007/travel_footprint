#!/bin/bash
# increment_version.sh

# 读取当前版本
current=$(grep 'version:' pubspec.yaml | sed 's/version: //' | tr -d '\r')
base=${current%+*}
build=${current#*+}
new_build=$((build + 1))
new_version="$base+$new_build"

# 替换
sed -i '' "s/version: $current/version: $new_version/" pubspec.yaml
echo "版本已更新为: $new_version"