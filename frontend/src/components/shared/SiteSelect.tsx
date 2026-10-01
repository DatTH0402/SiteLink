/**
 * SiteSelect – searchable site picker (server-side search, 30 results at a time).
 * Replaces loading every site into the cell form.
 * Works as a controlled antd <Form.Item> child (value / onChange).
 */
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Select, Spin } from 'antd'
import { getSites, getSite } from '@/api/sites'
import type { Site } from '@/types'

interface Props {
  value?: number
  onChange?: (value: number | undefined) => void
  onSiteChange?: (site: Site | undefined) => void
  disabled?: boolean
  placeholder?: string
}

export default function SiteSelect({
  value, onChange, onSiteChange, disabled,
  placeholder = 'Gõ tên site để tìm...',
}: Props) {
  const [options,  setOptions]  = useState<Site[]>([])
  const [selected, setSelected] = useState<Site | undefined>()
  const [loading,  setLoading]  = useState(false)
  const reqRef   = useRef(0)
  const timerRef = useRef<number | undefined>(undefined)

  const search = (text: string, delay = 250) => {
    window.clearTimeout(timerRef.current)
    timerRef.current = window.setTimeout(async () => {
      const id = ++reqRef.current
      setLoading(true)
      try {
        const rows = await getSites({
          search: text.trim() || undefined, limit: 30,
          sort_by: 'site_name', sort_dir: 'asc',
        })
        if (id === reqRef.current) setOptions(rows)
      } catch { /* keep old options */ }
      finally { if (id === reqRef.current) setLoading(false) }
    }, delay)
  }

  useEffect(() => { search('', 0); return () => window.clearTimeout(timerRef.current) }, [])

  // make sure the current value can be displayed (edit mode)
  useEffect(() => {
    if (!value) { setSelected(undefined); return }
    if (selected?.id === value) return
    getSite(value).then(setSelected).catch(() => {})
  }, [value])

  const list = useMemo(() => {
    const m = new Map<number, Site>()
    if (selected) m.set(selected.id, selected)
    options.forEach((s) => m.set(s.id, s))
    return [...m.values()]
  }, [options, selected])

  return (
    <Select
      showSearch allowClear filterOption={false}
      disabled={disabled} placeholder={placeholder}
      value={value} loading={loading}
      onSearch={(t) => search(t)}
      notFoundContent={loading ? <Spin size="small" /> : 'Không tìm thấy site'}
      onChange={(v: number | undefined) => {
        const s = list.find((x) => x.id === v)
        setSelected(s)
        onChange?.(v)
        onSiteChange?.(s)
      }}
      options={list.map((s) => ({ value: s.id, label: s.site_name }))}
    />
  )
}
