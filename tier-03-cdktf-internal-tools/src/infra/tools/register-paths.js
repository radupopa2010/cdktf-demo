// Loads tsconfig-paths but disables the matchAll fallback so that a bare
// `cdktf` import doesn't resolve against `./cdktf.json` (which has the same
// stem as the package, with `resolveJsonModule` enabled). Without this, the
// cdktf-cli config file shadows the npm package and `cdktf.TerraformProvider`
// becomes undefined at runtime.
const path = require("path");
const tsconfigPaths = require("tsconfig-paths");

const projectRoot = path.resolve(__dirname, "..", "..", "..");

tsconfigPaths.register({
  baseUrl: projectRoot,
  paths: {
    "@providers/*": ["./out/gen/providers/*"],
    "@modules/*": ["./out/gen/modules/*"],
  },
  addMatchAll: false,
});
