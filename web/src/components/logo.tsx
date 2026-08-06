import Image from "next/image";
import logoLight from "../../public/copyonce-logo-light.png";
import logoDark from "../../public/copyonce-logo-dark.png";
import { cn } from "./ui";

/**
 * The CopyOnce lockup — the same mark the app ships.
 *
 * The wordmark is part of the artwork, so this replaces a text lockup rather
 * than sitting beside one.
 *
 * Both variants render, stacked, and CSS fades to one. Swapping a `src` from
 * JavaScript would flash the wrong logo before hydration, and hiding one with
 * display:none would stop it downloading — so switching theme would leave a gap
 * where the mark should be. The rules in globals.css mirror the palette's
 * cascade exactly, so a manual light/dark choice moves the logo with
 * everything else.
 */
export function Logo({
  height = 28,
  className,
  priority = false,
}: {
  height?: number;
  className?: string;
  /** Set on the first logo above the fold so it is not lazy-loaded. */
  priority?: boolean;
}) {
  // The source is a wide horizontal lockup; width follows from its ratio.
  const width = Math.round(height * (logoLight.width / logoLight.height));

  return (
    <span
      className={cn("logo-stack shrink-0 align-middle", className)}
      style={{ height }}
    >
      <Image
        src={logoLight}
        alt="CopyOnce"
        width={width}
        height={height}
        priority={priority}
        className="logo-light"
      />
      <Image
        src={logoDark}
        alt="CopyOnce"
        width={width}
        height={height}
        priority={priority}
        aria-hidden="true"
        className="logo-dark"
      />
    </span>
  );
}
