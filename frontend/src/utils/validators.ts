/**
 * validators.ts
 * Shared Ant Design form validators for SiteLink.
 *
 * NOTE: do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt (cells) and
 *       do_cao_dinh_cot_anten, do_cao_cot_anten (sites) are now STRING fields.
 * They accept any non-empty string (e.g. "35", "IBC", "N/A").
 * Only lat/long remain purely numeric with range validation.
 */

// Vietnam bounding box (lat/long remain float with range validation)
export const VN_LAT_MIN = 8.33
export const VN_LAT_MAX = 23.39
export const VN_LON_MIN = 102.14
export const VN_LON_MAX = 109.47

export const latValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Latitude phải là số'))
  if (v < VN_LAT_MIN || v > VN_LAT_MAX)
    return Promise.reject(
      new Error(`Latitude phải trong khoảng ${VN_LAT_MIN} – ${VN_LAT_MAX} (lãnh thổ Việt Nam)`)
    )
  return Promise.resolve()
}

export const lonValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Longitude phải là số'))
  if (v < VN_LON_MIN || v > VN_LON_MAX)
    return Promise.reject(
      new Error(`Longitude phải trong khoảng ${VN_LON_MIN} – ${VN_LON_MAX} (lãnh thổ Việt Nam)`)
    )
  return Promise.resolve()
}

/**
 * azimuthValidator – now accepts any non-empty string.
 * Numeric values are still checked for 0–359 range as a soft warning,
 * but non-numeric strings (e.g. "IBC") pass without error.
 */
export const azimuthValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && (v < 0 || v > 359))
    return Promise.reject(new Error('Azimuth số phải trong khoảng 0 – 359'))
  return Promise.resolve()
}

/**
 * positiveNumberValidator – now accepts any non-empty string.
 * Numeric values are still checked for >= 0 as a soft warning,
 * but non-numeric strings (e.g. "IBC") pass without error.
 */
export const positiveNumberValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && v < 0)
    return Promise.reject(new Error('Giá trị số phải >= 0'))
  return Promise.resolve()
}

/**
 * tiltValidator – accepts any non-empty string.
 * Numeric values checked for -90 to 90 range as soft warning.
 */
export const tiltValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && (v < -90 || v > 90))
    return Promise.reject(new Error('Tilt số thường trong khoảng -90 đến 90'))
  return Promise.resolve()
}
