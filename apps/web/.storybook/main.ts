import type { StorybookConfig } from "@storybook/nextjs";

const config: StorybookConfig = {
  stories: ["../src/**/*.stories.@(ts|tsx)"],
  addons: ["@storybook/addon-vitest"],
  framework: {
    name: "@storybook/nextjs",
    options: {},
  },
  // Previously empty -- every story using a /public asset (the octopus mark, background images,
  // etc.) silently 404'd inside Storybook's iframe, since nothing served the public/ folder there.
  staticDirs: ["../public"],
};

export default config;
