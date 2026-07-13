export function createMockPage() {
  const actions = [];
  const mockLocator = (selector) => ({
    fill: async (value) => {
      actions.push({ type: "fill", selector, value });
    },
    click: async () => {
      actions.push({ type: "click", selector });
    },
    first: () => ({
      click: async () => {
        actions.push({ type: "click", selector });
      },
    }),
  });

  return {
    actions,
    goto: async (url) => {
      actions.push({ type: "goto", url });
    },
    waitForTimeout: async (ms) => {
      actions.push({ type: "waitForTimeout", ms });
    },
    waitForLoadState: async () => {
      actions.push({ type: "waitForLoadState" });
    },
    locator: mockLocator,
  };
}
