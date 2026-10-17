/*
 * Traffic value formatting.
 *
 * Ported 1:1 from ClashMetaForAndroid:
 *   core/src/main/java/com/github/kr328/clash/core/util/Traffic.kt
 *
 * Android packs a Traffic value into a 64-bit Long:
 *   bits 63..32 = upload, bits 31..0 = download
 * and each 32-bit half is itself packed:
 *   bits 31..30 = unit type (0=bytes, 1=KiB, 2=MiB, 3=GiB)
 *   bits 29..0  = scaled data
 *
 * The two halves are unpacked before reaching this module, so the 64-bit
 * packing never has to be reproduced here.
 */

/** Unpack one 32-bit traffic half into a byte count. Mirrors Kotlin `scaleTraffic`. */
export function scaleTraffic(value: number): number {
  const type: number = (value >>> 30) & 0x3;
  const data: number = value & 0x3FFFFFFF;
  return data * Math.pow(1024, type);
}

/**
 * Format a scaled byte count. Mirrors Kotlin `trafficString`, including its
 * integer-division-then-divide-by-100 behaviour (which is what produces the
 * two decimal places without a float rounding difference).
 */
export function trafficString(scaled: number): string {
  if (scaled > 1024 * 1024 * 1024 * 100) {
    const data: number = Math.floor(scaled / 1024 / 1024 / 1024);
    return `${(data / 100).toFixed(2)} GiB`;
  }
  if (scaled > 1024 * 1024 * 100) {
    const data: number = Math.floor(scaled / 1024 / 1024);
    return `${(data / 100).toFixed(2)} MiB`;
  }
  if (scaled > 1024 * 100) {
    const data: number = Math.floor(scaled / 1024);
    return `${(data / 100).toFixed(2)} KiB`;
  }
  return `${scaled} Bytes`;
}

/** Total forwarded traffic (upload + download). Mirrors Kotlin `trafficTotal`. */
export function trafficTotal(uploadPacked: number, downloadPacked: number): string {
  const upload: number = scaleTraffic(uploadPacked);
  const download: number = scaleTraffic(downloadPacked);
  return trafficString(upload + download);
}

/**
 * Format a plain byte total.
 *
 * IMPORTANT -- why this multiplies by 100.
 *
 * `trafficString` expects a "scaled" figure that is BYTES x 100, not bytes.
 * That is not obvious from its name, but it follows from the Android pair:
 *
 *   scaleTraffic(data, type) = data * 1024^type
 *   trafficString(scaled)    = (scaled / 1024^type) / 100
 *
 * The core packs `data` in hundredths of the unit, so `scaleTraffic` really
 * returns bytes x 100, and `trafficString` divides that 100 back out. The two
 * only agree when the input to `trafficString` is bytes x 100.
 *
 * The external-controller API reports plain bytes, so the x100 has to be
 * applied here. Without it the figure renders 100x too small -- which is
 * exactly what the first end-to-end run against a mock controller showed
 * (140 KiB of forwarded traffic displayed as "1.40 KiB").
 */
export function trafficFromBytes(uploadBytes: number, downloadBytes: number): string {
  return trafficString((uploadBytes + downloadBytes) * 100);
}
