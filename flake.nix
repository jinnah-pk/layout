{
  description =
    "A simple flake to expose Jupyter port for Paddle OCR Docker container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        server = ''
            # Copy the server script
            cp ${pkgs.writeText "paddleocr-server" ''
              #!${pkgs.python3}/bin/python
               # [A server for PaddleOCR]
                import socket
                import sys
                import paddleocr
                from io import BytesIO
                from PIL import Image
                import base64
                import json

                def process_image(data):
                    image = Image.open(BytesIO(data))
                    ocr = paddleocr.PaddleOCR(lang="en")
                    result = ocr.ocr(image)
                    return result

                def main():
                    if len(sys.argv) != 2:
                        print(f"Usage: {sys.argv[0]} <port>")
                        sys.exit(1)

                    port = int(sys.argv[1])

                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                        s.bind(("0.0.0.0", port))
                        s.listen(1)

                        print(f"Listening on port {port}")

                        while True:
                            conn, addr = s.accept()
                            with conn:
                                print(f"Connected by {addr}")
                                data = conn.recv(1024 * 1024)  # 1 MB buffer
                                if data:
                                    result = process_image(data)
                                    response = json.dumps(result).encode("utf-8")
                                    conn.sendall(response)
                                else:
                                    print("No data received")

                if __name__ == "__main__":
                    main()

            ''} paddleocr-server

            chmod +x paddleocr-server
          '';
        pkgs = import nixpkgs { inherit system; };
        ocrServerImage = pkgs.dockerTools.buildImage {
          name = "ocr-server";
          fromImage = pkgs.dockerTools.pullImage {
            imageName = "paddlecloud/paddleocr";
            finalImageTag = "2.6-cpu-d1a3c1";
            imageDigest =
              "sha256:69e3d025fc012e321da0fbeba13c68a0288218e53c9aa9167ca1bb9088c2491b";
            sha256 =
              "026eae305dc389c6e43f72f6afad50b7fd5898e6c89f325cd1c9d071fc3c2472";
          };
          runAsRoot = server;
          config = { Cmd = [ "python" "paddleocr-server" "8074" ]; };
        };
      in {
        defaultPackage = pkgs.writeShellScriptBin "run-paddle-ocr" ''
          #!${pkgs.runtimeShell}
          ${pkgs.docker}/bin/docker load -i ${ocrServerImage}
          ${pkgs.docker}/bin/docker run -p 8074:8074 ocr-server
        '';

        nixosModule = { ... }: {
          systemd.services.paddle-ocr = {
            description = "Paddle OCR Jupyter Server";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${self.defaultPackage.${system}}/bin/run-paddle-ocr";
              Restart = "always";
              RestartSec = "5s";
            };
          };
        };
      });
}
