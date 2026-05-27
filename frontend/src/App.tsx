import React, { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { useAuthStore } from '@/store/auth'
import { getMe } from '@/api/auth'

import LoginPage       from '@/pages/auth/LoginPage'
import MainLayout      from '@/components/layout/MainLayout'
import DashboardPage   from '@/pages/dashboard/DashboardPage'
import ReportPage      from '@/pages/dashboard/ReportPage'
import SitesPage       from '@/pages/sites/SitesPage'
import SiteFormPage    from '@/pages/sites/SiteFormPage'
import Cells3GPage     from '@/pages/cells/Cells3GPage'
import Cells4GPage     from '@/pages/cells/Cells4GPage'
import Cells5GPage     from '@/pages/cells/Cells5GPage'
import UsersPage       from '@/pages/admin/UsersPage'
import AuditPage       from '@/pages/admin/AuditPage'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  if (!user) return <Navigate to="/login" replace />
  if (user.role !== 'admin') return <Navigate to="/" replace />
  return <>{children}</>
}

export default function App() {
  const { token, setAuth, logout } = useAuthStore()

  useEffect(() => {
    if (token) {
      getMe().then((u) => setAuth(u, token)).catch(() => logout())
    }
  }, [])

  return (
    <>
      <Toaster position="top-right" />
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/"
          element={
            <PrivateRoute>
              <MainLayout />
            </PrivateRoute>
          }
        >
          <Route index element={<DashboardPage />} />
          <Route path="report"          element={<ReportPage />} />
          <Route path="sites"           element={<SitesPage />} />
          <Route path="sites/new"       element={<SiteFormPage />} />
          <Route path="sites/:id/edit"  element={<SiteFormPage />} />
          <Route path="cells/3g"        element={<Cells3GPage />} />
          <Route path="cells/4g"        element={<Cells4GPage />} />
          <Route path="cells/5g"        element={<Cells5GPage />} />
          <Route path="admin/users"     element={<AdminRoute><UsersPage /></AdminRoute>} />
          <Route path="admin/audit"     element={<AdminRoute><AuditPage /></AdminRoute>} />
        </Route>
      </Routes>
    </>
  )
}
