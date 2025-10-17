final: prev: {
  hello-script = prev.writeShellScriptBin "hello" "echo Hello World, how are you today!";
}
