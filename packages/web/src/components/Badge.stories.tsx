import type { Meta, StoryObj } from '@storybook/react-vite'
import { Badge } from './Badge'

const meta = {
  title: 'Components/Badge',
  component: Badge,
  parameters: { layout: 'centered' },
} satisfies Meta<typeof Badge>

export default meta
type Story = StoryObj<typeof meta>

export const Outline: Story = {
  args: { variant: 'outline', children: 'Safe smart account required' },
}

export const Dot: Story = {
  args: { variant: 'dot', children: 'Aqua routing' },
}
