// Dependency-free regression checks; these do not replace visual browser testing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../docs/landing/prototype.html'), 'utf8');
const script = html.split('<script>')[1].split('</script>')[0];
new vm.Script(script);

const animations = [];
class Element {
  constructor() { this.style = {}; }
  animate(frames, options) {
    const animation = {
      target: this, frames, options,
      cancel() { this.cancelled = true; },
      finish() { this.onfinish?.(); }
    };
    animations.push(animation);
    return animation;
  }
}
const summary = {
  nextSibling: null,
  getBoundingClientRect: () => ({ height: 24 }),
  addEventListener(type, callback) { this.click = callback; }
};
const details = Object.assign(new Element(), {
  open: false,
  querySelector: () => summary,
  append(content) { this.content = content; },
  removeAttribute() {}, toggleAttribute() {},
  getBoundingClientRect() { return { height: this.open ? 160 : 40 }; }
});
const document = {
  createElement: () => Object.assign(new Element(), {
    append() {},
    // Closed details descendants can retain geometry despite not being painted.
    getBoundingClientRect: () => ({ height: 120 })
  }),
  querySelectorAll: selector => selector === 'details' ? [details] : []
};
vm.runInNewContext(script.slice(script.indexOf('const motionEasing=')), {
  Element, document, window: {},
  getComputedStyle: () => ({ paddingTop: '8px', paddingBottom: '7px', borderTopWidth: '0px', borderBottomWidth: '1px' })
});
const click = () => summary.click({ preventDefault() {} });
click();
assert.equal(animations.at(-1).target, details, 'Animate the visible details box, not hidden-descendant geometry');
assert.equal(animations.at(-1).frames[0].height, '40px');
assert.equal(animations.at(-1).frames[1].height, '160px');
animations.at(-1).finish();
assert.equal(details.open, true);
assert.equal(details.style.height, '');
click();
assert.equal(animations.at(-1).frames[1].height, '40px');
animations.at(-1).finish();
assert.equal(details.open, false);
assert.equal(details.content.inert, true);
click();
const interrupted = animations.at(-1);
click();
assert.equal(interrupted.cancelled, true);
animations.at(-1).finish();
assert.equal(details.open, false);
assert.equal(details.style.overflow, '');
console.log('Landing motion checks passed: distinct height endpoints, open/close, interruption, and style cleanup.');
