#!/bin/sh
# Fails when an endpoint or domain of a China-based service shows up in what the app ships.
#
# Scanned: app/src/main (code, manifest, resources and assets) and core/src/main, except
# core/src/main/resources/knowledge/, the on-screen know-how for phone apps and sites
# (for example how to use the WeChat app), which may name such sites on purpose.
#
# Needs only sh and grep (-r and -I are supported by GNU and BSD grep). Runs from any directory.
# Exit status: 0 nothing found, 1 something found, 2 the check itself failed.
#
#   sh woowtech/tools/check-no-cn-services.sh

set -u

case "$0" in
    */*) here=${0%/*} ;;
    *) here=. ;;
esac
if ! cd "$here/../.."; then
    echo "check-no-cn-services: cannot change to the repository root" >&2
    exit 2
fi

for dir in app/src/main core/src/main; do
    if [ ! -d "$dir" ]; then
        echo "check-no-cn-services: $dir not found; run this script from inside the repository" >&2
        exit 2
    fi
done

# What to scan: app/src/main, and core/src/main without core/src/main/resources/knowledge.
set -- app/src/main
for entry in core/src/main/*; do
    [ -e "$entry" ] || continue
    if [ "$entry" = core/src/main/resources ]; then
        for res in core/src/main/resources/*; do
            [ -e "$res" ] || continue
            [ "$res" = core/src/main/resources/knowledge ] || set -- "$@" "$res"
        done
    else
        set -- "$@" "$entry"
    fi
done

# Domains of the removed China-based services, matched as fixed strings, ignoring case.
matches=$(grep -r -n -I -i -F \
    -e deepseek.com \
    -e aliyuncs.com \
    -e aliyun.com \
    -e moonshot.cn \
    -e moonshot.ai \
    -e bigmodel.cn \
    -e zhipuai.cn \
    -e siliconflow.cn \
    -e siliconflow.com \
    -e volces.com \
    -e volcengine.com \
    -e volcengineapi.com \
    -e bytepluses.com \
    -e doubao.com \
    -e minimax.cn \
    -e minimaxi.com \
    -e minimax.chat \
    -e minimax.io \
    -e stepfun.com \
    -e tencentmaas.com \
    -e hunyuan.cloud.tencent.com \
    -e baidubce.com \
    -e weixin.qq.com \
    -e bytedance.com \
    -- "$@")
status=$?

case $status in
    0)
        echo "check-no-cn-services: endpoints of China-based services found in shipped code:" >&2
        printf '%s\n' "$matches" >&2
        echo "check-no-cn-services: remove them. Only core/src/main/resources/knowledge/ may name such sites." >&2
        exit 1
        ;;
    1)
        echo "check-no-cn-services: no China-based service endpoints in app/src/main or core/src/main."
        exit 0
        ;;
    *)
        echo "check-no-cn-services: grep failed (exit status $status)" >&2
        exit 2
        ;;
esac
