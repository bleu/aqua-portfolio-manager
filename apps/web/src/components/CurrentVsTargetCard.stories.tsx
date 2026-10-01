import type { Meta, StoryObj } from '@storybook/react-vite'
import { CurrentVsTargetCard } from './CurrentVsTargetCard'

const meta = {
  title: 'Components/CurrentVsTargetCard',
  component: CurrentVsTargetCard,
  parameters: { layout: 'padded' },
  decorators: [
    (Story) => (
      <div style={{ width: 560 }}>
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof CurrentVsTargetCard>

export default meta
type Story = StoryObj<typeof meta>

export const TwoBaskets: Story = {
  args: {
    baskets: [
      {
        label: 'Crypto majors',
        currentPct: 42,
        targetPct: 33.3,
        caption: 'Routing reduces the overweight basket toward 33.3%',
      },
      {
        label: 'Stablecoins',
        currentPct: 58,
        targetPct: 66.7,
        caption: 'Routing increases the underweight basket toward 66.7%',
      },
    ],
  },
}

export const ThreeBaskets: Story = {
  args: {
    baskets: [
      {
        label: 'Crypto majors',
        currentPct: 50,
        targetPct: 40,
        caption: 'Routing reduces the overweight basket toward 40%',
      },
      {
        label: 'Stablecoins',
        currentPct: 30,
        targetPct: 40,
        caption: 'Routing increases the underweight basket toward 40%',
      },
      {
        label: 'LSTs',
        currentPct: 20,
        targetPct: 20,
        caption: 'Already at target -- no routing needed',
      },
    ],
  },
}
