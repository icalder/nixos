{ remotePkgs, ... }:
final: prev: {
  hello-world-server = remotePkgs.hello-world-server;
}
