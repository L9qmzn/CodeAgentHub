from __future__ import annotations

import socket

from cc_B.app_factory import create_app
from cc_B.config import CONFIG

app = create_app()


def _detect_local_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"


if __name__ == "__main__":
    import uvicorn

    port_value = CONFIG.get("port")
    try:
        port = int(port_value) if port_value is not None else 8207
    except ValueError:
        port = 8207

    local_ip = _detect_local_ip()
    url = f"http://{local_ip}:{port}"

    print("================ Claude 服务启动参数 ================")
    for key in sorted(CONFIG.keys()):
        print(f"{key}: {CONFIG[key]}")
    print(f"resolved_port: {port}")
    print(f"local_url: {url}")
    print("====================================================")

    uvicorn.run("cc_B.main:app", host="0.0.0.0", port=port, reload=False)
