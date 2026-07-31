// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "vectie/moonchat"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/vectie/moonchat"

license = "Apache-2.0"

keywords = [ ]

description = ""

import {
  "moonbitlang/async@0.20.2",
  "moonbitlang/x@0.4.46",
  "vectie/moonlib@0.1.19",
}
