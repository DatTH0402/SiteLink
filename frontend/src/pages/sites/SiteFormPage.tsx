import React, { useEffect, useState, useCallback } from 'react'
import {
  Typography, Form, Input, Select, Switch, Button,
  Row, Col, Card, Space, InputNumber, message,
} from 'antd'
import { SaveOutlined, ArrowLeftOutlined } from '@ant-design/icons'
import { useNavigate, useParams } from 'react-router-dom'
import { getSite, createSite, updateSite } from '@/api/sites'
import { getDropdown, getTinhList, getTinhXaPhuong } from '@/api/report'
import type { TinhItem, PhuongXaItem } from '@/types'

export default function SiteFormPage() {
  const [form]   = Form.useForm()
  const navigate = useNavigate()
  const { id }   = useParams<{ id: string }>()
  const isEdit   = Boolean(id)

  const [loading,         setLoading]         = useState(false)
  const [phanLoaiOpts,    setPhanLoaiOpts]    = useState<string[]>([])
  const [tinhList,        setTinhList]        = useState<TinhItem[]>([])
  const [phuongXaList,    setPhuongXaList]    = useState<PhuongXaItem[]>([])
  const [selectedTinh,    setSelectedTinh]    = useState<string | undefined>()
  const [loadingPhuongXa, setLoadingPhuongXa] = useState(false)

  useEffect(() => {
    getDropdown('phan_loai_tram').then((rows: any[]) =>
      setPhanLoaiOpts(rows.map((r) => r.value)))
    getTinhList().then((rows: TinhItem[]) => setTinhList(rows))

    if (isEdit && id) {
      getSite(Number(id)).then((site) => {
        form.setFieldsValue(site)
        if (site.tinh) setSelectedTinh(site.tinh)
      })
    }
  }, [id])

  useEffect(() => {
    if (!selectedTinh) { setPhuongXaList([]); return }
    setLoadingPhuongXa(true)
    getTinhXaPhuong(selectedTinh)
      .then((rows: PhuongXaItem[]) => setPhuongXaList(rows))
      .finally(() => setLoadingPhuongXa(false))
  }, [selectedTinh])

  const handleTinhChange = useCallback((value: string) => {
    setSelectedTinh(value)
    form.setFieldValue('phuong_xa', undefined)
    const found = tinhList.find((t) => t.ten_tinh === value)
    if (found) form.setFieldValue('mien', found.mien)
  }, [tinhList, form])

  const onFinish = async (values: any) => {
    setLoading(true)
    try {
      if (isEdit) {
        await updateSite(Number(id), values)
        message.success('Cập nhật site thành công')
      } else {
        await createSite(values)
        message.success('Tạo site mới thành công')
      }
      navigate('/sites')
    } catch (e: any) {
      const detail = e.response?.data?.detail || 'Có lỗi xảy ra'
      if (typeof detail === 'string' && detail.includes('already exists')) {
        message.warning(`Site đã tồn tại: ${values.site_name}`)
      } else {
        message.error(typeof detail === 'string' ? detail : 'Có lỗi xảy ra')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/sites')}>
          Quay lại
        </Button>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isEdit ? 'Chỉnh sửa Site' : 'Thêm Site mới'}
        </Typography.Title>
      </Space>

      <Form form={form} layout="vertical" onFinish={onFinish}>
        <Card title="Thông tin chung" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={4}>
              <Form.Item name="mien" label="Miền">
                <Select placeholder="Chon mien" allowClear>
                  {['MB', 'MT', 'MN'].map((m) => (
                    <Select.Option key={m} value={m}>{m}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={10}>
              <Form.Item name="tinh" label="Tỉnh / Thành phố"
                         rules={[{ required: true, message: 'Vui lòng chọn tỉnh' }]}>
                <Select
                  showSearch allowClear
                  placeholder="Chọn tỉnh / thành phố..."
                  optionFilterProp="children"
                  onChange={handleTinhChange}
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())
                  }
                >
                  {tinhList.map((t) => (
                    <Select.Option key={t.ten_tinh} value={t.ten_tinh}>
                      {t.ten_tinh}
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={10}>
              <Form.Item name="phuong_xa" label="Phường / Xã">
                <Select
                  showSearch allowClear
                  placeholder={selectedTinh ? 'Chọn phường / xã...' : 'Chọn tỉnh trước'}
                  disabled={!selectedTinh}
                  loading={loadingPhuongXa}
                  optionFilterProp="children"
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())
                  }
                >
                  {phuongXaList.map((p) => (
                    <Select.Option key={p.id} value={p.ten_phuong_xa}>
                      {p.ten_phuong_xa}
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name_cu" label="Site name (cũ)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name" label="Site name"
                         rules={[{ required: true, message: 'Vui lòng nhập site name' }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="site_vip" label="Site VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="ma_ptm" label="Mã PTM">
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Toạ độ và Cột anten" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item
                name="lat"
                label="Latitude"
                rules={[{
                  validator: (_: unknown, value: number) => {
                    if (value === undefined || value === null) return Promise.resolve()
                    if (value < 8.33 || value > 23.39)
                      return Promise.reject('Latitude phải trong khoảng 8.33 – 23.39 (Việt Nam)')
                    return Promise.resolve()
                  }
                }]}
              >
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001}
                  placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item
                name="long"
                label="Longitude"
                rules={[{
                  validator: (_: unknown, value: number) => {
                    if (value === undefined || value === null) return Promise.resolve()
                    if (value < 102.14 || value > 109.47)
                      return Promise.reject('Longitude phải trong khoảng 102.14 – 109.47 (Việt Nam)')
                    return Promise.resolve()
                  }
                }]}
              >
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001}
                  placeholder="102.14 – 109.47" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_dinh_cot_anten" label="Độ cao đỉnh cột anten (m)">
                <InputNumber style={{ width: '100%' }} min={0} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_cot_anten" label="Độ cao cột anten mặt đất (m)">
                <InputNumber style={{ width: '100%' }} min={0} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Loại trạm và Công nghệ" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={8}>
              <Form.Item name="phan_loai_tram" label="Phân loại trạm">
                <Select allowClear>
                  {phanLoaiOpts.map((o) => (
                    <Select.Option key={o} value={o}>{o}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            {([
              ['tram_2g',            'Trạm 2G'],
              ['tram_3g',            'Trạm 3G'],
              ['tram_4g',            'Trạm 4G'],
              ['tram_5g',            'Trạm 5G'],
              ['repeater',           'Repeater'],
              ['booster',            'Booster'],
              ['node_truyen_dan_only','Node truyền dẫn only'],
              ['tram_phu_song_tsca', 'Trạm phủ sóng TSCA'],
            ] as [string, string][]).map(([name, label]) => (
              <Col span={4} key={name}>
                <Form.Item name={name} label={label} valuePropName="checked">
                  <Switch />
                </Form.Item>
              </Col>
            ))}
          </Row>
          <Row gutter={16}>
            {([
              ['moran_3g', 'MORAN 3G'],
              ['moran_4g', 'MORAN 4G'],
              ['moran_5g', 'MORAN 5G'],
            ] as [string, string][]).map(([name, label]) => (
              <Col span={6} key={name}>
                <Form.Item name={name} label={label}>
                  <Select allowClear>
                    <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                    <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                  </Select>
                </Form.Item>
              </Col>
            ))}
          </Row>
        </Card>

        <Card title="Thông tin khác" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="dia_chi" label="Địa chỉ">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="ghi_chu" label="Ghi chú">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Space>
          <Button type="primary" htmlType="submit" icon={<SaveOutlined />} loading={loading}>
            {isEdit ? 'Cập nhật' : 'Tạo mới'}
          </Button>
          <Button onClick={() => navigate('/sites')}>Hủy</Button>
        </Space>
      </Form>
    </div>
  )
}
