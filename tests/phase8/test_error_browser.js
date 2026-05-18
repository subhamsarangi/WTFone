// Phase 8 Browser Test using Playwright
// Tests robust error handling and edge cases in the browser
// Run: npx playwright test tests/phase8/test_error_browser.js

const { test, expect } = require('@playwright/test');

const PASSWORD = 'test123';

test.describe('Phase 8: Robust Error Handling Browser Tests', () => {

  test('UI displays error when creating room with empty password', async ({ page }) => {
    await page.goto('/');
    
    // Switch to Create tab
    await page.click('#tabCreate');
    
    // Attempt creation with empty password field
    await page.click('#authActionBtn');

    // Verify error status displays correct validation
    const status = page.locator('#status');
    await expect(status).toBeVisible();
    await expect(status).toHaveClass(/error/);
    await expect(status).toContainText('Password required');
  });

  test('UI displays error when joining a non-existent room', async ({ page }) => {
    await page.goto('/');
    
    // Fill in a non-existent UUID and password
    const fakeRoomId = '00000000-0000-0000-0000-000000000000';
    await page.fill('#roomId', fakeRoomId);
    await page.fill('#password', PASSWORD);
    
    // Submit join request
    await page.click('#authActionBtn');
    
    // Verify console line logs errors gracefully
    const errorLog = page.locator('.console-line.error').first();
    await expect(errorLog).toBeVisible({ timeout: 5000 });
  });
});
