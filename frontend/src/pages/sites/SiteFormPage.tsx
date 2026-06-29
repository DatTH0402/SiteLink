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
        message.success('Cap nhat site thanh cong')
      } else {
        await createSite(values)
        message.success('Tao site moi thanh cong')
      }
      navigate('/sites')
    } catch (e: any) {
      const detail = e.response?.data?.detail || 'Co loi xay ra'
      if (typeof detail === 'string' && detail.includes('already exists')) {
        message.warning(`Site da ton tai: ${values.site_name}`)
      } else {
        message.error(typeof detail === 'string' ? detail : 'Co loi xay ra')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/sites')}>
          Quay lai
        </Button>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isEdit ? 'Chinh sua Site' : 'Them Site moi'}
        </Typography.Title>
      </Space>

      <Form form={form} layout="vertical" onFinish={onFinish}>
        <Card title="Thong tin chung" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={4}>
              <Form.Item name="mien" label="Mien">
                <Select placeholder="Chon mien" allowClear>
                  {['MB', 'MT', 'MN'].map((m) => (
                    <Select.Option key={m} value={m}>{m}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={10}>
              <Form.Item name="tinh" label="Tinh / Thanh pho"
                         rules={[{ required: true, message: 'Vui long chon tinh' }]}>
                <Select
                  showSearch allowClear
                  placeholder="Chon tinh / thanh pho..."
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
              <Form.Item name="phuong_xa" label="Phuong / Xa">
                <Select
                  showSearch allowClear
                  placeholder={selectedTinh ? 'Chon phuong / xa...' : 'Chon tinh truoc'}
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
              <Form.Item name="site_name_cu" label="Site name (cu)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name" label="Site name"
                         rules={[{ required: true, message: 'Vui long nhap site name' }]}>
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
              <Form.Item name="ma_ptm" label="Ma PTM">
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Toa do va Col anten" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item name="lat" label="Latitude">
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="long" label="Longitude">
                <InputNumber style={{ width: '100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_dinh_cot_anten" label="Do cao dinh cot anten (m)">
                <InputNumber style={{ width: '100%' }} min={0} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_cot_anten" label="Do cao cot anten mat san (m)">
                <InputNumber style={{ width: '100%' }} min={0} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Loai tram va Cong nghe" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={8}>
              <Form.Item name="phan_loai_tram" label="Phan loai tram">
                <Select allowClear>
                  {phanLoaiOpts.map((o) => (
                    <Select.Option key={o} value={o}>{o}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            {([
              ['tram_2g',            'Tram 2G'],
              ['tram_3g',            'Tram 3G'],
              ['tram_4g',            'Tram 4G'],
              ['tram_5g',            'Tram 5G'],
              ['repeater',           'Repeater'],
              ['booster',            'Booster'],
              ['node_truyen_dan_only','Node truyen dan only'],
              ['tram_phu_song_tsca', 'Tram phu song TSCA'],
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

        <Card title="Thong tin khac" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="dia_chi" label="Dia chi">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="ghi_chu" label="Ghi chu">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Space>
          <Button type="primary" htmlType="submit" icon={<SaveOutlined />} loading={loading}>
            {isEdit ? 'Cap nhat' : 'Tao moi'}
          </Button>
          <Button onClick={() => navigate('/sites')}>Huy</Button>
        </Space>
      </Form>
    </div>
  )
}
