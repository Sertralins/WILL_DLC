// 可选校验：只在外部临时目录安装官方运行库，不把它打包进游戏。
// node tools/validate_qyy_spine.mjs <spine-core/dist/index.js> <Godot probe 输出 JSON>
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const runtime = await import(pathToFileURL(resolve(process.argv[2])).href);
const { TextureAtlas, AtlasAttachmentLoader, SkeletonJson, Skeleton, Physics, MixBlend, MixDirection } = runtime;
const root = fileURLToPath(new URL('../assets/spine/qyy/', import.meta.url));
const atlas = new TextureAtlas(readFileSync(resolve(root, 'qyy.atlas'), 'utf8'));
const loader = new SkeletonJson(new AtlasAttachmentLoader(atlas));
const data = loader.readSkeletonData(readFileSync(resolve(root, 'qyy.json'), 'utf8'));
assert.equal(data.bones.length, 7);
assert.equal(data.animations[0].duration, 8);
assert.equal(atlas.regions[0].width, 512);
assert.equal(atlas.regions[0].height, 1024);
const skeleton = new Skeleton(data);
const samples = JSON.parse(readFileSync(process.argv[3], 'utf8'));
let maximumError = 0;
for (const sample of samples) {
  skeleton.setToSetupPose();
  data.animations[0].apply(skeleton, 0, sample.time, false, [], 1, MixBlend.replace, MixDirection.mixIn);
  skeleton.updateWorldTransform(Physics.none);
  const slot = skeleton.slots[0];
  const mesh = slot.getAttachment();
  const points = new Float32Array(mesh.worldVerticesLength);
  mesh.computeWorldVertices(slot, 0, points.length, points, 0, 2);
  assert.equal(points.length, sample.vertices.length);
  points.forEach((value, i) => {
    assert.ok(Number.isFinite(value));
    maximumError = Math.max(maximumError, Math.abs(value - sample.vertices[i]));
  });
}
assert.ok(maximumError < 0.002, `Godot/Spine mismatch: ${maximumError}`);
console.log(`OFFICIAL_SPINE: parsed atlas, skeleton and idle; ${samples.length} poses match Godot; max error ${maximumError.toFixed(6)} px`);
