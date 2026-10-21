import { useEffect, useState } from 'react'
import { getBadge, FEEDBACK_CHANGED } from '@/api/feedback'

/** number shown next to the "Hỗ trợ / Góp ý" menu item (polls every 60s) */
export function useFeedbackBadge(): number {
  const [n, setN] = useState(0)
  useEffect(() => {
    let stopped = false
    const tick = () => {
      if (document.hidden) return
      getBadge().then((c) => { if (!stopped) setN(c) }).catch(() => {})
    }
    tick()
    const id = window.setInterval(tick, 60_000)
    const onVis = () => { if (!document.hidden) tick() }
    document.addEventListener('visibilitychange', onVis)
    window.addEventListener(FEEDBACK_CHANGED, tick)
    return () => {
      stopped = true
      window.clearInterval(id)
      document.removeEventListener('visibilitychange', onVis)
      window.removeEventListener(FEEDBACK_CHANGED, tick)
    }
  }, [])
  return n
}
