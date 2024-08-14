{ config, lib, pkgs, ... }: let
  key = "/var/keystore/secrets.key";
  mountpoint = "/run/secrets";
  active = "${mountpoint}/active";
in {
  options.secrets = let
    secret = lib.types.submodule ({ name, ... }: {
      options = {
        decrypted = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = ''
            Path to decrypted secret
          '';
        };
        encrypted = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to age-encrypted secret
          '';
        };
        uid = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = ''
            Decrypted secret owner UID
          '';
        };
        gid = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = ''
            Decrypted secret owned GID
          '';
        };
        permissions = lib.mkOption {
          type = lib.types.str;
          default = "400";
          description = ''
            Permissions to set on decrypted secret
          '';
        };
      };
      config.decrypted = "${active}/${name}";
      config.name = name;
    });
  in lib.mkOption {
    type = lib.types.attrsOf secret;
    default = {};
  };

  config.system.activationScripts = let
    script = "secrets";
    secrets = builtins.attrValues config.secrets;
    decrypt = secret: let
      path = "$tmp/${secret.name}";
    in ''
      mkdir --parents --mode 755 $(dirname "${path}")
      ${pkgs.age}/bin/age --decrypt --identity "${key}" -o "${path}" "${secret.encrypted}"
      chmod 555 $(dirname "${path}")
      chmod ${secret.permissions} "${path}"
      chown ${builtins.toString secret.uid}:${builtins.toString secret.gid} "${path}"
    '';
  in {
    ${script} = {
      deps = [ "specialfs" ];
      text = ''
        # prepare mountpoint
        mkdir -pm 755 "${mountpoint}"
        grep -q "${mountpoint}" /proc/mounts || mount -t ramfs none "${mountpoint}" -o nodev,nosuid,mode=755

        # prepare clean new secrets directory
        tmp=$(mktemp -d "${mountpoint}/XXXXXXXX")

        ${lib.concatMapStrings decrypt secrets}

        # read-only access to filenames for everyone
        chmod 555 "$tmp"

        # atomically switch active secrets
        ln --symbolic --force --no-dereference "$tmp" "${active}"
      '';
    };
    users.deps = [ script ];
  };
}
