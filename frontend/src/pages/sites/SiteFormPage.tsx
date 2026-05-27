import React, { useEffect, useState } from 'react'
import {
  Typography, Form, Input, Select, Switch, Button,
  Row, Col, Card, Space, InputNumber, message,
} from 'antd'
import { SaveOutlined, ArrowLeftOutlined } from '@ant-design/icons'
import { useNavigate, useParams } from 'react-router-dom'
import { getSite, createSite, updateSite } from '@/api/sites'
import { getDropdown } from '@/api/report'

export default function SiteFormPage() {
  const [form]    = Form.useForm()
  const navigate  = useNavigate()
  const { id }    = useParams<{ id: string }>()
  const isEdit    = Boolean(id)
  const [loading,      setLoading]      = useState(false)
  const [phanLoaiOpts, setPhanLoaiOpts] = useState<string[]>([])

  useEffect(() => {
    getDropdown('phan_loai_tram').then((rows: any[]) =>
      setPhanLoaiOpts(rows.map((r) => r.value)))
    if (isEdit && id) {
      getSite(Number(id)).then((site) => form.setFieldsValue(site))
    }
  }, [id])

  const onFinish = async (values: any) => {
    setLoading(true)
    try {
      if (isEdit) {
        await updateSite(Number(id), values)
        message.success('Cap nhat thanh cong')
      } else {
        await createSite(values)
        message.success('Tao site thanh cong')
      }
      navigate('/sites')
    } catch (e: any) {
      message.error(e.response?.data?.detail || 'Co loi xay ra')
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
            <Col span={6}>
              <Form.Item name="mien" label="Mien" rules={[{ required: true }]}>
                <Select>
                  {['MB','MT','MN'].map((m) =>
                    <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={9}>
              <Form.Item name="tinh" label="Tinh" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={9}>
              <Form.Item name="phuong_xa" label="Phuong/Xa">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name_cu" label="Site name (cu)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name" label="Site name" rules={[{ required: true }]}>
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
              <Form.Item name="ma_ptm" label="Ma PTM" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Toa do and Col anten" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item name="lat" label="Latitude" rules={[{ required: true }]}>
                <InputNumber style={{ width:'100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="long" label="Longitude" rules={[{ required: true }]}>
                <InputNumber style={{ width:'100%' }} precision={5} step={0.00001} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_dinh_cot_anten" label="Do cao dinh cot anten (m)">
                <InputNumber style={{ width:'100%' }} min={0} />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="do_cao_cot_anten" label="Do cao cot anten mat san (m)">
                <InputNumber style={{ width:'100%' }} min={0} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Loai tram and Cong nghe" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={8}>
              <Form.Item name="phan_loai_tram" label="Phan loai tram">
                <Select allowClear>
                  {phanLoaiOpts.map((o) =>
                    <Select.Option key={o} value={o}>{o}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            {([
              ['tram_2g','Tram 2G'],['tram_3g','Tram 3G'],
              ['tram_4g','Tram 4G'],['tram_5g','Tram 5G'],
              ['repeater','Repeater'],['booster','Booster'],
              ['node_truyen_dan_only','Node truyen dan only'],
            ] as [string,string][]).map(([name, label]) => (
              <Col span={4} key={name}>
                <Form.Item name={name} label={label} valuePropName="checked">
                  <Switch />
                </Form.Item>
              </Col>
            ))}
          </Row>
          <Row gutter={16}>
            {([
              ['moran_3g','MORAN 3G'],
              ['moran_4g','MORAN 4G'],
              ['moran_5g','MORAN 5G'],
            ] as [string,string][]).map(([name, label]) => (
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
          <Button type="primary" htmlType="submit"
                  icon={<SaveOutlined />} loading={loading}>
            {isEdit ? 'Cap nhat' : 'Tao moi'}
          </Button>
          <Button onClick={() => navigate('/sites')}>Huy</Button>
        </Space>
      </Form>
    </div>
  )
}
