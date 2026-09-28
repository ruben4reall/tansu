// PNG helpers without dependencies: the size of a picture, and the text chunk that marks a placeholder, so that a
// placeholder can never be mistaken for a real capture (tests/release.test.mjs checks it before publishing).
import { crc32 } from 'node:zlib';

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
export const PLACEHOLDER_TEXT = 'Comment\0tiroir-placeholder';

export function isPng(buffer) {
  return buffer.length > 33 && buffer.subarray(0, 8).equals(SIGNATURE);
}

/** Width and height in pixels, from the IHDR chunk. */
export function pngSize(buffer) {
  if (!isPng(buffer)) throw new Error('not a PNG');
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

/** Every chunk as { type, data }. */
export function pngChunks(buffer) {
  const chunks = [];
  for (let offset = 8; offset + 8 <= buffer.length;) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('latin1', offset + 4, offset + 8);
    chunks.push({ type, data: buffer.subarray(offset + 8, offset + 8 + length) });
    offset += 12 + length;
    if (type === 'IEND') break;
  }
  return chunks;
}

export function isPlaceholder(buffer) {
  return isPng(buffer) && pngChunks(buffer).some((c) => c.type === 'tEXt' && c.data.toString('latin1') === PLACEHOLDER_TEXT);
}

/** A one-picture .ico file that holds a PNG (every browser since 2007 reads it). */
export function pngToIco(png) {
  const { width, height } = pngSize(png);
  const header = Buffer.alloc(22);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // an icon
  header.writeUInt16LE(1, 4); // one picture
  header.writeUInt8(width >= 256 ? 0 : width, 6);
  header.writeUInt8(height >= 256 ? 0 : height, 7);
  header.writeUInt16LE(1, 10); // colour planes
  header.writeUInt16LE(32, 12); // bits per pixel
  header.writeUInt32LE(png.length, 14);
  header.writeUInt32LE(22, 18); // where the PNG starts
  return Buffer.concat([header, png]);
}

/** The PNG inside a one-picture .ico file. */
export function icoPng(ico) {
  return ico.subarray(ico.readUInt32LE(18), ico.readUInt32LE(18) + ico.readUInt32LE(14));
}

/** The same picture with a tEXt chunk "Comment: tiroir-placeholder" right after IHDR. */
export function markPlaceholder(buffer) {
  if (isPlaceholder(buffer)) return buffer;
  const type = Buffer.from('tEXt', 'latin1');
  const data = Buffer.from(PLACEHOLDER_TEXT, 'latin1');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([type, data])) >>> 0);
  const afterHeader = 8 + 12 + buffer.readUInt32BE(8);
  return Buffer.concat([buffer.subarray(0, afterHeader), length, type, data, crc, buffer.subarray(afterHeader)]);
}
