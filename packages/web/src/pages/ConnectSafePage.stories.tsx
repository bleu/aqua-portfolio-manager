import type { Meta, StoryObj } from '@storybook/react-vite'
import { fn } from 'storybook/test'
import { ConnectSafePage } from './ConnectSafePage'

const meta = {
  title: 'Pages/ConnectSafePage',
  component: ConnectSafePage,
  parameters: { layout: 'fullscreen' },
  args: { onConnectSafe: fn() },
} satisfies Meta<typeof ConnectSafePage>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
