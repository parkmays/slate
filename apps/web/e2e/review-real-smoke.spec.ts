import { expect, test } from '@playwright/test'

test.describe('real review smoke', () => {
  test.skip(process.env.REVIEW_E2E_REAL !== '1', 'Set REVIEW_E2E_REAL=1 to run non-mock smoke tests.')

  test('loads review page and core layout', async ({ page }) => {
    await page.goto('/review/playwright-valid-token')

    await expect(page.getByText(/Select a clip to begin review|Annotations|Clips/i)).toBeVisible()
    await expect(page.locator('video').first()).toBeVisible()
  })
})
