import type { CSSProperties } from "react";
import { cn } from "@/lib/cn";

type Box = { left?: number; right?: number; top: number; width: number; height: number };

export type DecorProps = {
  src: string;
  /** The box Figma reports for the rotated layer (its bounding box), in px inside the parent.
   *  Use `right` instead of `left` to keep the layer attached to the parent's right edge. */
  wrapper: Box;
  /** The layer's own, unrotated size in px. */
  size: { width: number; height: number };
  /** CSS transform of the layer. Order matters: Figma flips first, then rotates. */
  transform?: CSSProperties["transform"];
  className?: string;
};

/** A decorative, rotated brand illustration placed exactly as in Figma: a centred box for the
 *  rotated bounding box, with the unrotated layer transformed inside it. */
export function Decor({ src, wrapper, size, transform, className }: DecorProps) {
  return (
    <div
      aria-hidden="true"
      className={cn("pointer-events-none absolute flex items-center justify-center", className)}
      style={{ left: wrapper.left, right: wrapper.right, top: wrapper.top, width: wrapper.width, height: wrapper.height }}
    >
      <div className="flex-none" style={{ width: size.width, height: size.height, transform }}>
        <img src={src} alt="" className="block size-full max-w-none" />
      </div>
    </div>
  );
}

export type TiltedProps = {
  wrapper: Box;
  size: { width: number; height?: number };
  transform?: CSSProperties["transform"];
  className?: string;
  children: React.ReactNode;
};

/** Same placement as `Decor`, for live content (cards) instead of an image. */
export function Tilted({ wrapper, size, transform, className, children }: TiltedProps) {
  return (
    <div
      className="absolute flex items-center justify-center"
      style={{ left: wrapper.left, right: wrapper.right, top: wrapper.top, width: wrapper.width, height: wrapper.height }}
    >
      <div className={cn("flex-none", className)} style={{ width: size.width, height: size.height, transform }}>
        {children}
      </div>
    </div>
  );
}
