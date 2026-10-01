{pkgs, ...}: {
  packages = with pkgs; [
    just
    stylua
    selene
  ];
  languages.rust.enable = true;
  languages.lua.enable = true;
}
