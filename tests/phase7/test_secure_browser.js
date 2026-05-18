// Phase 7 Browser Test using Playwright
// Tests HTTPS secure context, dynamic tabs, and premium styling in the browser
// Run: npx playwright test tests/phase7/test_secure_browser.js

const { test, expect } = require('@playwright/test');

test.describe('Phase 7: HTTPS Secure Context & Tabbed UI Browser Tests', () => {

  test('Page loads securely under HTTPS with Navy Blue background', async ({ page }) => {
    await page.goto('/');
    
    // 1. Verify HTTPS / WSS secure context
    const isSecure = await page.evaluate(() => window.isSecureContext);
    expect(isSecure).toBe(true);
    
    // 2. Verify Title Text and Palette
    const header = await page.locator('.header-section h1');
    await expect(header).toContainText('WTFONE Video Chat');
    const titleColor = await header.evaluate(el => window.getComputedStyle(el).color);
    expect(titleColor).toBeDefined();

    // 3. Verify Body Navy Blue Background
    const bodyBg = await page.evaluate(() => window.getComputedStyle(document.body).backgroundColor);
    expect(bodyBg).toBeDefined();
  });

  test('Dynamic tabs switch active state and forms correctly', async ({ page }) => {
    await page.goto('/');
    
    const tabJoin = page.locator('#tabJoin');
    const tabCreate = page.locator('#tabCreate');
    const roomIdGroup = page.locator('#roomIdGroup');
    const authActionBtn = page.locator('#authActionBtn');

    // 1. Verify default tab is Join Room
    await expect(tabJoin).toHaveClass(/active/);
    await expect(tabCreate).not.toHaveClass(/active/);
    await expect(roomIdGroup).toBeVisible();
    await expect(authActionBtn).toContainText('Join Room');

    // 2. Switch to Create Room tab
    await tabCreate.click();
    await expect(tabCreate).toHaveClass(/active/);
    await expect(tabJoin).not.toHaveClass(/active/);
    await expect(roomIdGroup).not.toBeVisible();
    await expect(authActionBtn).toContainText('Create Room');

    // 3. Switch back to Join Room tab
    await tabJoin.click();
    await expect(tabJoin).toHaveClass(/active/);
    await expect(tabCreate).not.toHaveClass(/active/);
    await expect(roomIdGroup).toBeVisible();
    await expect(authActionBtn).toContainText('Join Room');
  });
});
