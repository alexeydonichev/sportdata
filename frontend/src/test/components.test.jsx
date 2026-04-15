import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import React from 'react'

function StatusBadge({ status }) {
  const colors = {
    critical: 'bg-red-500',
    warning: 'bg-yellow-500',
    info: 'bg-blue-500',
  }
  return React.createElement('span', {
    'data-testid': 'badge',
    className: colors[status] || 'bg-gray-500'
  }, status)
}

function MetricCard({ title, value, change }) {
  const isPositive = change > 0
  return React.createElement('div', { 'data-testid': 'card' }, [
    React.createElement('h3', { key: 'h' }, title),
    React.createElement('span', { key: 'v', 'data-testid': 'value' }, String(value)),
    React.createElement('span', {
      key: 'c',
      'data-testid': 'change',
      className: isPositive ? 'text-green' : 'text-red'
    }, (isPositive ? '+' : '') + change + '%')
  ])
}

describe('StatusBadge', () => {
  it('renders critical red', () => {
    render(React.createElement(StatusBadge, { status: 'critical' }))
    expect(screen.getByTestId('badge')).toHaveTextContent('critical')
    expect(screen.getByTestId('badge')).toHaveClass('bg-red-500')
  })
  it('renders warning yellow', () => {
    render(React.createElement(StatusBadge, { status: 'warning' }))
    expect(screen.getByTestId('badge')).toHaveClass('bg-yellow-500')
  })
  it('unknown gets fallback', () => {
    render(React.createElement(StatusBadge, { status: 'unknown' }))
    expect(screen.getByTestId('badge')).toHaveClass('bg-gray-500')
  })
})

describe('MetricCard', () => {
  it('renders title and value', () => {
    render(React.createElement(MetricCard, { title: 'Revenue', value: 12345, change: 5.2 }))
    expect(screen.getByText('Revenue')).toBeTruthy()
    expect(screen.getByTestId('value')).toHaveTextContent('12345')
  })
  it('positive change is green', () => {
    render(React.createElement(MetricCard, { title: 'X', value: 1, change: 10 }))
    expect(screen.getByTestId('change')).toHaveClass('text-green')
    expect(screen.getByTestId('change')).toHaveTextContent('+10%')
  })
  it('negative change is red', () => {
    render(React.createElement(MetricCard, { title: 'X', value: 1, change: -3 }))
    expect(screen.getByTestId('change')).toHaveClass('text-red')
    expect(screen.getByTestId('change')).toHaveTextContent('-3%')
  })
})
