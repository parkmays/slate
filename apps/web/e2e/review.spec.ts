import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.route('**/api/proxy-url', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        signedUrl: 'https://cdn.example.com/mock-video.m3u8',
        thumbnailUrl: 'https://cdn.example.com/mock-thumb.jpg',
        expiresAt: '2099-01-01T00:00:00.000Z',
      }),
    })
  })

  await page.route('**/api/annotations', async (route) => {
    const payload = route.request().postDataJSON() as {
      clipId: string
      timecodeIn: string
      body: string
      type: 'text' | 'voice'
    }

    await route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        annotation: {
          id: `annotation-${Date.now()}`,
          userId: 'share-token',
          userDisplayName: 'Reviewer',
          timecodeIn: payload.timecodeIn,
          timecodeOut: null,
          body: payload.body,
          type: payload.type,
          voiceUrl: null,
          createdAt: '2026-03-31T12:00:00.000Z',
          resolvedAt: null,
          isResolved: false,
          mentions: [],
          replies: [],
        },
      }),
    })
  })

  await page.route('**/api/clips/*/status', async (route) => {
    const payload = route.request().postDataJSON() as { reviewStatus: string }
    const clipId = route.request().url().split('/').slice(-2)[0]

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        clipId,
        status: payload.reviewStatus,
        updatedAt: '2026-03-31T12:00:00.000Z',
      }),
    })
  })

  await page.route('**/api/clips/*/request-alternate', async (route) => {
    const payload = route.request().postDataJSON() as {
      note: string
      timecodeIn: string
    }

    await route.fulfill({
      status: 201,
      contentType: 'application/json',
      body: JSON.stringify({
        annotation: {
          id: `alternate-${Date.now()}`,
          userId: 'share-token',
          userDisplayName: 'Reviewer',
          timecodeIn: payload.timecodeIn,
          timecodeOut: null,
          body: `REQUEST ALTERNATE: ${payload.note}`,
          type: 'text',
          voiceUrl: null,
          createdAt: '2026-03-31T12:00:00.000Z',
          resolvedAt: null,
          isResolved: false,
          mentions: [],
          replies: [],
        },
      }),
    })
  })

  await page.route('**/api/assembly/*', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue()
      return
    }

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'assembly-1',
        title: 'Assembly Preview',
        versionLabel: 'v4',
        artifactPath: 'exports/assembly-1.fcpxml',
        clips: [
          {
            id: 'assembly-clip-1',
            clipId: 'mock-clip-1',
            label: 'Opening beat',
            order: 1,
            timecodeIn: '01:00:00:00',
            timecodeOut: '01:00:12:00',
            duration: '00:00:12:00',
          },
        ],
      }),
    })
  })
})

test('password-gated link rejects a wrong password and opens with the correct password', async ({ page }) => {
  await page.goto('/review/playwright-password-token')

  await expect(page.getByRole('heading', { name: 'Password Protected' })).toBeVisible()

  await page.getByLabel('Password').fill('wrong-password')
  await page.getByRole('button', { name: 'Unlock' }).click()
  await expect(page.getByText('Invalid password')).toBeVisible()
  await expect(page).toHaveURL(/\/review\/playwright-password-token$/)

  await page.getByLabel('Password').fill('review123')
  await page.getByRole('button', { name: 'Unlock' }).click()
  await expect(page.getByRole('heading', { name: 'Playwright Review Project' })).toBeVisible()
  await expect(page).toHaveURL(/\/review\/playwright-password-token$/)
})

test('expired tokens show the expired access state', async ({ page }) => {
  await page.goto('/review/playwright-expired-token')

  await expect(page.getByRole('heading', { name: 'Review Link Expired' })).toBeVisible()
  await expect(page.getByText(/share link has expired/i)).toBeVisible()
})

test('submitting an annotation shows it in the list', async ({ page }) => {
  await page.goto('/review/playwright-valid-token')

  await expect(page.getByTestId('proxy-player-shell')).toBeVisible()
  await page.getByTestId('annotation-textarea').fill('Playwright smoke annotation')
  await page.getByTestId('post-annotation').click()

  await expect(page.getByText('Playwright smoke annotation')).toBeVisible()
})

test('status updates mark the clip as circled', async ({ page }) => {
  await page.goto('/review/playwright-valid-token')

  await page.getByTestId('review-status-circled').click()
  await expect(page.getByTestId('review-status-circled')).toHaveAttribute('data-active', 'true')
})

test('request alternate submits a note and shows confirmation', async ({ page }) => {
  await page.goto('/review/playwright-valid-token')

  await page.getByRole('button', { name: 'Request Alt' }).click()
  await page.getByPlaceholder('Describe what you need…').fill('Need a cleaner alt for this line.')
  await page.getByRole('button', { name: 'Submit' }).click()

  await expect(page.getByText('Alternate request sent.')).toBeVisible()
})

test('AI scores panel renders all gauge rows for a scored clip', async ({ page }) => {
  await page.goto('/review/playwright-valid-token')

  await page.getByRole('button', { name: 'AI Scores' }).click()
  await expect(page.getByTestId('ai-scores-panel')).toBeVisible()
  await expect(page.getByText('Composite')).toBeVisible()
  await expect(page.getByText('Focus')).toBeVisible()
  await expect(page.getByText('Exposure')).toBeVisible()
  await expect(page.getByText('Stability')).toBeVisible()
  await expect(page.getByText('Audio')).toBeVisible()
})

test('Transcript tab shows mock transcript segments from review fixtures', async ({ page }) => {
  await page.goto('/review/playwright-valid-token')

  await page.getByRole('button', { name: 'Transcript' }).click()
  await expect(page.getByText('The line lands cleanly here.')).toBeVisible()
  await expect(page.getByText('Try a softer pickup on the second sentence.')).toBeVisible()
})
