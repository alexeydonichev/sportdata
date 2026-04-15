import { describe, it, expect, vi, beforeEach } from 'vitest'

const mockFetch = vi.fn()
global.fetch = mockFetch

const API_BASE = '/api'

async function apiGet(path, token) {
  const headers = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = 'Bearer ' + token
  const res = await fetch(API_BASE + path, { headers })
  if (res.ok === false) throw new Error('HTTP ' + res.status)
  return res.json()
}

async function apiPost(path, data, token) {
  const headers = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = 'Bearer ' + token
  const res = await fetch(API_BASE + path, {
    method: 'POST', headers, body: JSON.stringify(data)
  })
  return res.json()
}

function mockOk(data) {
  return { ok: true, status: 200, json: () => Promise.resolve(data) }
}

function mockErr(status) {
  return { ok: false, status, json: () => Promise.resolve({ error: 'fail' }) }
}

describe('API client', () => {
  beforeEach(() => mockFetch.mockReset())

  it('GET sends auth header', async () => {
    mockFetch.mockResolvedValue(mockOk({ data: 1 }))
    await apiGet('/dashboard', 'mytoken')
    expect(mockFetch).toHaveBeenCalledWith('/api/dashboard', {
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer mytoken' }
    })
  })

  it('GET throws on 401', async () => {
    mockFetch.mockResolvedValue(mockErr(401))
    await expect(apiGet('/dashboard', 'bad')).rejects.toThrow('HTTP 401')
  })

  it('GET throws on 500', async () => {
    mockFetch.mockResolvedValue(mockErr(500))
    await expect(apiGet('/sales')).rejects.toThrow('HTTP 500')
  })

  it('POST sends body', async () => {
    mockFetch.mockResolvedValue(mockOk({ token: 'abc' }))
    const result = await apiPost('/auth/login', { username: 'admin', password: 'pass' })
    expect(result.token).toBe('abc')
    expect(mockFetch).toHaveBeenCalledWith('/api/auth/login', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ username: 'admin', password: 'pass' })
    }))
  })

  it('GET without token has no auth header', async () => {
    mockFetch.mockResolvedValue(mockOk({}))
    await apiGet('/health')
    const call = mockFetch.mock.calls[0]
    expect(call[1].headers.Authorization).toBeUndefined()
  })
})
