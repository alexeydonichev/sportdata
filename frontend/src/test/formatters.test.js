import { describe, it, expect } from 'vitest'

function formatMoney(value) {
  if (value == null) return '0 rub'
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 0 }).format(value) + ' rub'
}

function formatPercent(value) {
  if (value == null) return '0%'
  return (value > 0 ? '+' : '') + value.toFixed(1) + '%'
}

function formatNumber(value) {
  if (value == null) return '0'
  return new Intl.NumberFormat('ru-RU').format(value)
}

function daysLeftColor(days) {
  if (days <= 0) return 'red'
  if (days <= 7) return 'orange'
  if (days <= 14) return 'yellow'
  return 'green'
}

function parsePeriod(p) {
  const m = p.match(/^(\d+)([dwmy])$/)
  if (!m) return null
  return { value: parseInt(m[1]), unit: m[2] }
}

describe('formatMoney', () => {
  it('formats positive', () => {
    const r = formatMoney(1234)
    expect(r).toContain('1')
    expect(r).toContain('rub')
  })
  it('handles zero', () => expect(formatMoney(0)).toContain('0'))
  it('handles null', () => expect(formatMoney(null)).toBe('0 rub'))
  it('handles negative', () => expect(formatMoney(-500)).toContain('500'))
})

describe('formatPercent', () => {
  it('positive gets +', () => expect(formatPercent(12.5)).toBe('+12.5%'))
  it('negative no +', () => expect(formatPercent(-5.3)).toBe('-5.3%'))
  it('zero', () => expect(formatPercent(0)).toBe('0.0%'))
  it('null', () => expect(formatPercent(null)).toBe('0%'))
})

describe('formatNumber', () => {
  it('separators', () => expect(formatNumber(1234567)).toMatch(/1.*234.*567/))
  it('null', () => expect(formatNumber(null)).toBe('0'))
})

describe('daysLeftColor', () => {
  it('0 days = red', () => expect(daysLeftColor(0)).toBe('red'))
  it('3 days = orange', () => expect(daysLeftColor(3)).toBe('orange'))
  it('10 days = yellow', () => expect(daysLeftColor(10)).toBe('yellow'))
  it('30 days = green', () => expect(daysLeftColor(30)).toBe('green'))
  it('negative = red', () => expect(daysLeftColor(-1)).toBe('red'))
})

describe('parsePeriod', () => {
  it('7d', () => expect(parsePeriod('7d')).toEqual({ value: 7, unit: 'd' }))
  it('30d', () => expect(parsePeriod('30d')).toEqual({ value: 30, unit: 'd' }))
  it('invalid', () => expect(parsePeriod('abc')).toBeNull())
  it('12m', () => expect(parsePeriod('12m')).toEqual({ value: 12, unit: 'm' }))
})
