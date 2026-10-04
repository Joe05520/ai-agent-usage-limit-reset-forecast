#!/bin/zsh
set -eu
cd "${0:A:h:h}"
xcodebuild -project OpenAIUsageSentinel.xcodeproj -scheme OpenAIUsageSentinel -configuration Release -derivedDataPath build build
xcodebuild -project OpenAIUsageSentinel.xcodeproj -scheme OpenAIUsageSentinel -configuration Debug -derivedDataPath build test
swift test
open 'build/Build/Products/Release/Usage Sentinel.app'
