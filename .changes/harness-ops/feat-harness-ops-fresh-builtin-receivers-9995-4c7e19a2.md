---
bump: minor
---

### Added

- **The parser reader's sink rule clears receivers that a built-in constructor makes fresh.** Under `--reader=parser`, `new` of a built-in constructor named by its unshadowed global name (`Error` and the other native errors, `Map`, `Set`, `WeakMap`, `WeakSet`) is a fresh object. So is `this` in the constructor of a class extending one, as in `class Qs extends Error{constructor(e){super(e);Object.setPrototypeOf(this,Qs.prototype)}}`, and so is `new` of that class. A computed write, a computed define or a prototype swap on such a receiver is no longer a sink. Each clearance trusts the constructor's name, so a module that may replace it (`Error=f`, `globalThis.Map=f`) is a sink instead. A call that passes the name as a string, such as `tagTester("Error")`, is not a sink, the same rule as for `Object`. A class extending a built-in counts only while every reference to it is a `new`, a named member read that writes nothing, the right of `instanceof`, a superclass or an `export{...}`: `super()` calls the class's own prototype, and a prototype swap on the class could make `this` any object.

### Fixed

- The parser reader's sink rule now counts two more prototype swaps, in any module: `Reflect.set(o,"__proto__",p)`, and an own `__proto__` property given to `Object.assign` (`Object.assign(o,{["__proto__"]:p})`). Each runs the `Object.prototype.__proto__` setter on `o`. Before, neither was a sink unless a trusted name was `__proto__`.
