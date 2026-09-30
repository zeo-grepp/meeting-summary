#!/bin/bash
# 처음 한 번만 실행한다. 이미 있는 것은 건너뛴다.
set -euo pipefail

cd "$(dirname "$0")"

[ "$(uname -sm)" = "Darwin arm64" ] || {
    echo "Apple Silicon Mac에서만 동작합니다 (전사에 mlx를 씁니다)." >&2
    exit 1
}

if ! command -v ffmpeg >/dev/null; then
    command -v brew >/dev/null || {
        echo "ffmpeg가 없고 Homebrew도 없습니다. https://brew.sh 에서 Homebrew를 먼저 설치해주세요." >&2
        exit 1
    }
    echo "ffmpeg를 설치합니다…"
    brew install ffmpeg
fi

if [ ! -x .venv/bin/python ]; then
    echo "가상환경을 만듭니다…"
    python3 -m venv .venv
fi

echo "패키지를 설치합니다… (처음에는 몇 분 걸립니다)"
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt

if [ ! -f claude_config.json ]; then
    printf '{\n  "api_key": "",\n  "base_url": "",\n  "model": ""\n}\n' > claude_config.json
    echo
    echo "claude_config.json을 만들었습니다. api_key를 채워주세요."
    echo "사내 게이트웨이를 쓴다면 base_url과 model도 채웁니다."
fi

echo
echo "설치 완료. 확인:  .venv/bin/python meeting.py --help"
