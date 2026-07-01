import React, { useState } from 'react'
import { Layout, Menu, Avatar, Dropdown, Space, Typography } from 'antd'
import {
  DashboardOutlined, DatabaseOutlined, TableOutlined,
  BarChartOutlined, UserOutlined, AuditOutlined,
  LogoutOutlined, MenuFoldOutlined, MenuUnfoldOutlined,
  WifiOutlined,
} from '@ant-design/icons'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'
import { ssoLogout } from '@/api/auth'

const { Sider, Header, Content } = Layout

export default function MainLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate   = useNavigate()
  const location   = useLocation()
  const { user, logout, idToken } = useAuthStore()

  const handleLogout = async () => {
    // Call SSO logout if we have id_token
    if (idToken) {
      try {
        await ssoLogout(idToken)
      } catch { /* ignore */ }
    }
    logout()
    navigate('/login')
  }

  const menuItems = [
    { key: '/',        icon: <DashboardOutlined />, label: 'Dashboard' },
    { key: '/report',  icon: <BarChartOutlined />,  label: 'Bao cao tong hop' },
    { key: '/sites',   icon: <DatabaseOutlined />,  label: 'Quan ly Site' },
    {
      key: 'cells',
      icon: <TableOutlined />,
      label: 'Quan ly Cell',
      children: [
        { key: '/cells/3g', label: 'Cell 3G' },
        { key: '/cells/4g', label: 'Cell 4G' },
        { key: '/cells/5g', label: 'Cell 5G' },
      ],
    },
    { key: '/antenna', icon: <WifiOutlined />, label: 'Quan ly Antenna' },
    ...(user?.role === 'admin'
      ? [{
          key: 'admin',
          icon: <AuditOutlined />,
          label: 'Quan tri',
          children: [
            { key: '/admin/users', label: 'Nguoi dung' },
            { key: '/admin/audit', label: 'Audit Log' },
          ],
        }]
      : []),
  ]

  const userMenu = {
    items: [{
      key: 'logout',
      icon: <LogoutOutlined />,
      label: 'Dang xuat',
      onClick: handleLogout,
    }],
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider collapsible collapsed={collapsed} onCollapse={setCollapsed}
             theme="dark" width={220}>
        <div style={{
          height: 48, display: 'flex', alignItems: 'center',
          justifyContent: 'center', color: '#fff',
          fontWeight: 700, fontSize: collapsed ? 14 : 18,
          borderBottom: '1px solid #333',
        }}>
          {collapsed ? 'SL' : 'SiteLink'}
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[location.pathname]}
          defaultOpenKeys={['cells', 'admin']}
          items={menuItems}
          onClick={({ key }) => {
            if (!['cells', 'admin'].includes(key)) navigate(key)
          }}
        />
      </Sider>

      <Layout>
        <Header style={{
          background: '#fff', padding: '0 24px',
          display: 'flex', alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: '1px solid #f0f0f0',
        }}>
          <Space>
            {collapsed
              ? <MenuUnfoldOutlined onClick={() => setCollapsed(false)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />
              : <MenuFoldOutlined   onClick={() => setCollapsed(true)}
                                    style={{ fontSize: 18, cursor: 'pointer' }} />}
            <Typography.Text strong style={{ fontSize: 16 }}>
              He thong quan ly du lieu toi uu
            </Typography.Text>
          </Space>
          <Dropdown menu={userMenu}>
            <Space style={{ cursor: 'pointer' }}>
              <Avatar icon={<UserOutlined />}
                      style={{ backgroundColor: user?.auth_provider === 'sso'
                        ? '#f5a623' : '#1890ff' }} />
              <span>
                {user?.full_name || user?.username}
                {user?.auth_provider === 'sso' && (
                  <span style={{ fontSize: 10, color: '#f5a623',
                                 marginLeft: 4 }}>[SSO]</span>
                )}
              </span>
            </Space>
          </Dropdown>
        </Header>

        <Content style={{
          margin: 16, padding: 16,
          background: '#fff', borderRadius: 8,
          minHeight: 'calc(100vh - 112px)',
          overflowY: 'auto',
        }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  )
}
