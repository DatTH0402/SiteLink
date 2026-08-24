/**
 * validators.ts
 * Shared Ant Design form validators for SiteLink.
 */

// Vietnam bounding box
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

export const azimuthValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Azimuth phải là số'))
  if (v < 0 || v > 359)
    return Promise.reject(new Error('Azimuth phải trong khoảng 0 – 359'))
  return Promise.resolve()
}

export const positiveNumberValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Giá trị phải là số'))
  if (v < 0) return Promise.reject(new Error('Giá trị phải >= 0'))
  return Promise.resolve()
}
