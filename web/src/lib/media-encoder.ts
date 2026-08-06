import { ALLOWED_IMAGE_TYPES } from "./types";

/** Longest edge of a generated thumbnail, matching thumbnailMaxEdge in Dart. */
export const THUMBNAIL_MAX_EDGE = 400;

/** Matches _thumbnailQuality in lib/services/media_encoder.dart. */
const THUMBNAIL_QUALITY = 0.78;

export class MediaError extends Error {}

/**
 * The image's real type, read from its leading bytes.
 *
 * Never trusts `File.type` or the filename. A file picker reports whatever the
 * OS claims, and an extension is an assertion, not evidence. This is the same
 * check MediaEncoder.sniffMimeType performs in the Flutter client, and it is
 * the reason an SVG renamed to .png still cannot get in — SVG can carry script.
 */
export async function sniffMimeType(blob: Blob): Promise<string | null> {
  const header = new Uint8Array(await blob.slice(0, 12).arrayBuffer());
  if (header.length < 12) return null;

  const at = (magic: number[], offset = 0) =>
    magic.every((byte, i) => header[offset + i] === byte);

  if (at([0xff, 0xd8, 0xff])) return "image/jpeg";
  if (at([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (at([0x47, 0x49, 0x46, 0x38])) return "image/gif";

  // RIFF....WEBP
  if (at([0x52, 0x49, 0x46, 0x46]) && at([0x57, 0x45, 0x42, 0x50], 8)) {
    return "image/webp";
  }

  // ....ftyp<brand> — the ISO base media container that HEIC also uses.
  if (at([0x66, 0x74, 0x79, 0x70], 4)) {
    const brand = String.fromCharCode(...header.slice(8, 12));
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) {
      return "image/heic";
    }
  }

  return null;
}

export function isAllowedImageType(mime: string | null): boolean {
  return mime !== null && (ALLOWED_IMAGE_TYPES as readonly string[]).includes(mime);
}

export function extensionFor(mime: string): string {
  switch (mime) {
    case "image/png":
      return "png";
    case "image/gif":
      return "gif";
    case "image/webp":
      return "webp";
    case "image/heic":
      return "heic";
    default:
      return "jpg";
  }
}

/** A decoded image plus how to let go of it, whichever path produced it. */
interface Decoded {
  source: CanvasImageSource;
  width: number;
  height: number;
  release: () => void;
}

/**
 * Decodes `blob`, preferring createImageBitmap and falling back to an <img>.
 *
 * The fast path applies EXIF orientation, so a portrait photo does not
 * thumbnail on its side. Safari only accepted the `imageOrientation` option
 * from version 17, and older iOS throws on it — which used to surface as "this
 * browser cannot read that image format", blaming the file for a browser
 * limitation.
 *
 * The <img> fallback works everywhere. It applies EXIF orientation itself in
 * every current browser, so the result is the same; it is only slower.
 */
async function decode(blob: Blob): Promise<Decoded> {
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(blob, {
        imageOrientation: "from-image",
      });
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        release: () => bitmap.close(),
      };
    } catch {
      // Either the option is unsupported or the format is not decodable here.
      // Let the fallback decide which.
    }
  }

  const url = URL.createObjectURL(blob);
  try {
    const image = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () =>
        reject(
          new MediaError(
            "This browser cannot read that image format. Try a JPEG or PNG, or send it from the app.",
          ),
        );
      el.src = url;
    });

    return {
      source: image,
      width: image.naturalWidth,
      height: image.naturalHeight,
      release: () => URL.revokeObjectURL(url),
    };
  } catch (error) {
    URL.revokeObjectURL(url);
    throw error;
  }
}

/**
 * Builds the list thumbnail: downscaled, re-encoded as JPEG.
 *
 * JPEG rather than WebP to match the Flutter client, whose image library only
 * encodes WebP losslessly. Keeping both clients on the same thumbnail format
 * means a thumbnail made on one renders on the other without special cases.
 *
 * Decoding goes through `decode` below, which applies EXIF orientation so a
 * portrait photo does not thumbnail on its side.
 */
export async function buildThumbnail(blob: Blob): Promise<Blob> {
  const bitmap = await decode(blob);
  const longest = Math.max(bitmap.width, bitmap.height);
  // Only ever shrink — upscaling costs bytes and adds nothing.
  const scale = longest <= THUMBNAIL_MAX_EDGE ? 1 : THUMBNAIL_MAX_EDGE / longest;

  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;

  const ctx = canvas.getContext("2d");
  if (!ctx) throw new MediaError("Could not process that image.");

  ctx.drawImage(bitmap.source, 0, 0, width, height);
  bitmap.release();

  const thumb = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", THUMBNAIL_QUALITY),
  );

  if (!thumb) throw new MediaError("Could not process that image.");
  return thumb;
}
