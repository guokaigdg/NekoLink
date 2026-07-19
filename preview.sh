#!/bin/bash
# NekoLink 快速构建 + 重启脚本
# 用法: ./preview.sh

set -e

echo "🚀 构建 NekoLink..."
cd "$(dirname "$0")"

xcodebuild -project NekoLink.xcodeproj \
    -scheme NekoLink \
    -configuration Debug \
    -destination 'platform=macOS' \
    build | tail -5

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "NekoLink.app" -type d 2>/dev/null | head -1)

if [ -z "$APP" ]; then
    echo "❌ 未找到构建产物"
    exit 1
fi

echo "🔄 重启应用..."
killall NekoLink 2>/dev/null || true
sleep 0.5
open "$APP"
echo "✅ 已启动"
