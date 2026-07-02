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
  if (value === undefined || value === null || value === 0) return Promise.resolve()
  if (value < VN_LAT_MIN || value > VN_LAT_MAX)
    return Promise.reject(
      new Error(`Latitude phai trong khoang ${VN_LAT_MIN} – ${VN_LAT_MAX} (lanh tho Viet Nam)`)
    )
  return Promise.resolve()
}

export const lonValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null || value === 0) return Promise.resolve()
  if (value < VN_LON_MIN || value > VN_LON_MAX)
    return Promise.reject(
      new Error(`Longitude phai trong khoang ${VN_LON_MIN} – ${VN_LON_MAX} (lanh tho Viet Nam)`)
    )
  return Promise.resolve()
}

export const azimuthValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  if (value < 0 || value > 359)
    return Promise.reject(new Error('Azimuth phai trong khoang 0 – 359'))
  return Promise.resolve()
}
