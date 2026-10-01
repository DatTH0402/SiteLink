/**
 * useTablePagination.tsx
 *
 * Controlled pagination for Ant Design <Table> (client-side data).
 *
 * Why: passing a literal `pageSize: 50` makes antd's page size controlled, so
 * choosing another size in the dropdown was always reset to 50.
 *
 * - keeps `current` and `pageSize` in state
 * - renders its own page-size selector (10 / 20 / 50 / 100 / Tất cả) inside
 *   `showTotal`, because antd's built-in size changer cannot show an "All" entry
 * - "All" => effective page size = total rows (everything on one page)
 *
 * Usage:
 *   const { pagination } = useTablePagination(data.length, 'cells')
 *   <Table dataSource={data} pagination={pagination} ... />
 */
import React, { useState } from 'react'
import { Select, Space } from 'antd'
import type { TablePaginationConfig } from 'antd/es/table'

export const PAGE_SIZE_ALL = 0
const PAGE_SIZES = [10, 20, 50, 100]

export function useTablePagination(
  total: number,
  unit = 'bản ghi',
  defaultPageSize = 50,
) {
  const [pageSize, setPageSize] = useState<number>(defaultPageSize)
  const [current,  setCurrent]  = useState<number>(1)

  const isAll         = pageSize === PAGE_SIZE_ALL
  const effectiveSize = isAll ? Math.max(total, 1) : pageSize
  const maxPage       = Math.max(1, Math.ceil(total / effectiveSize))
  const safeCurrent   = Math.min(current, maxPage)   // never beyond the last page

  const handleSizeChange = (size: number) => {
    setPageSize(size)
    setCurrent(1)
  }

  const pagination: TablePaginationConfig = {
    current: safeCurrent,
    pageSize: effectiveSize,
    showSizeChanger: false,            // replaced by the custom selector below
    onChange: (page) => setCurrent(page),
    showTotal: (t) => (
      <Space size={12}>
        <span>{t} {unit}</span>
        <Select
          size="small"
          value={pageSize}
          onChange={handleSizeChange}
          style={{ width: 130 }}
          options={[
            ...PAGE_SIZES.map((n) => ({ value: n, label: `${n} / trang` })),
            { value: PAGE_SIZE_ALL, label: 'Tất cả' },
          ]}
        />
      </Space>
    ),
  }

  return { pagination, pageSize, isAll }
}
