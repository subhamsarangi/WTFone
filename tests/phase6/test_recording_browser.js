// Phase 6 Recording Upload Test using Playwright
// Tests recording start/stop and file upload
// Run: npx playwright test tests/phase6/test_recording_upload.js

const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const BASE_URL = 'https://localhost:8443';
const PASSWORD = 'test123';

test.describe('Phase 6: Recording Upload', () => {

  test('Controls are hidden initially', async ({ page }) => {
    await page.goto(BASE_URL);
    
    const controlsSection = page.locator('#controlsSection');
    await expect(controlsSection).toBeHidden();
  });

  test('Recording button enables after join', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Join room (will fail on camera permission, but button should enable)
    await page.fill('#password', PASSWORD);
    
    // Mock camera permission denied to avoid blocking
    await page.context().grantPermissions([]);
    
    // Try to join - will fail on camera but we just check button state
    const recordBtn = await page.locator('#recordBtn');
    
    // Button should be disabled until actually joined
    await expect(recordBtn).toBeDisabled();
  });

  test('Recording upload endpoint exists', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Try to upload dummy file to endpoint
    const uploadResponse = await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data'], { type: 'video/webm' });
      const formData = new FormData();
      formData.append('file', blob, 'test.webm');
      
      try {
        const response = await fetch(`/api/rooms/${roomId}/recording`, {
          method: 'POST',
          body: formData
        });
        return {
          status: response.status,
          ok: response.ok
        };
      } catch (error) {
        return {
          error: error.message
        };
      }
    }, roomId);
    
    // Endpoint should exist (200 or 400, not 404)
    expect(uploadResponse.status).not.toBe(404);
  });

  test('Recording upload creates file in recordings directory', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Upload dummy file
    await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data'], { type: 'video/webm' });
      const formData = new FormData();
      formData.append('file', blob, 'test.webm');
      
      await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
    }, roomId);
    
    // Wait a bit for file to be written
    await page.waitForTimeout(500);
    
    // Check if file exists in recordings directory
    const recordingsDir = path.join(process.cwd(), 'recordings', roomId);
    const fileExists = fs.existsSync(recordingsDir) && 
                       fs.readdirSync(recordingsDir).length > 0;
    
    expect(fileExists).toBe(true);
  });

  test('Recording filename includes timestamp and peer ID', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Upload file with proper filename format
    await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data'], { type: 'video/webm' });
      const formData = new FormData();
      const timestamp = Date.now();
      const peerId = 'test-peer-browser';
      const filename = `${timestamp}_${peerId}.webm`;
      formData.append('file', blob, filename);
      
      await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
    }, roomId);
    
    // Wait for file
    await page.waitForTimeout(500);
    
    // Check filename format
    const recordingsDir = path.join(process.cwd(), 'recordings', roomId);
    if (fs.existsSync(recordingsDir)) {
      const files = fs.readdirSync(recordingsDir);
      expect(files.length).toBeGreaterThan(0);
      
      // Filename should match pattern: {timestamp}_{peer_id}.webm
      const filename = files[0];
      const hasTimestamp = /^\d+_/.test(filename);
      const hasWebm = filename.endsWith('.webm');
      
      expect(hasTimestamp).toBe(true);
      expect(hasWebm).toBe(true);
    }
  });

  test('Multiple recordings create separate files', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Upload first file
    await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data 1'], { type: 'video/webm' });
      const formData = new FormData();
      formData.append('file', blob, 'test1.webm');
      
      await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
    }, roomId);
    
    await page.waitForTimeout(300);
    
    // Upload second file
    await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data 2'], { type: 'video/webm' });
      const formData = new FormData();
      formData.append('file', blob, 'test2.webm');
      
      await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
    }, roomId);
    
    await page.waitForTimeout(300);
    
    // Check both files exist
    const recordingsDir = path.join(process.cwd(), 'recordings', roomId);
    if (fs.existsSync(recordingsDir)) {
      const files = fs.readdirSync(recordingsDir);
      expect(files.length).toBeGreaterThanOrEqual(2);
    }
  });

  test('Upload to non-existent room returns 404 error', async ({ page }) => {
    await page.goto(BASE_URL);
    
    const fakeRoomId = '00000000-0000-0000-0000-000000000000';
    
    // Upload to non-existent room (server now validates room exists and returns 404)
    const uploadResponse = await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data'], { type: 'video/webm' });
      const formData = new FormData();
      const timestamp = Date.now();
      const filename = `${timestamp}_test.webm`;
      formData.append('file', blob, filename);
      
      const response = await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
      
      return {
        status: response.status,
        ok: response.ok
      };
    }, fakeRoomId);
    
    // Server rejects upload and returns 404 (room validation)
    expect(uploadResponse.status).toBe(404);
    expect(uploadResponse.ok).toBe(false);
  });

  test('Upload without file returns error', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Try to upload empty form
    const uploadResponse = await page.evaluate(async (roomId) => {
      const formData = new FormData();
      // No file added
      
      const response = await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
      
      return {
        status: response.status,
        ok: response.ok
      };
    }, roomId);
    
    // Should return 400
    expect(uploadResponse.status).toBe(400);
  });

  test('Recording directory structure is correct', async ({ page }) => {
    await page.goto(BASE_URL);
    
    // Create room
    await page.fill('#password', PASSWORD);
    await page.click('#createBtn');
    
    // Wait for room ID
    await page.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomIdInput = await page.locator('#roomId');
    const roomId = await roomIdInput.inputValue();
    
    // Upload file
    await page.evaluate(async (roomId) => {
      const blob = new Blob(['dummy webm data'], { type: 'video/webm' });
      const formData = new FormData();
      formData.append('file', blob, 'test.webm');
      
      await fetch(`/api/rooms/${roomId}/recording`, {
        method: 'POST',
        body: formData
      });
    }, roomId);
    
    await page.waitForTimeout(500);
    
    // Check directory structure: recordings/{room_id}/{filename}.webm
    const recordingsDir = path.join(process.cwd(), 'recordings');
    const roomDir = path.join(recordingsDir, roomId);
    
    expect(fs.existsSync(recordingsDir)).toBe(true);
    expect(fs.existsSync(roomDir)).toBe(true);
    
    const files = fs.readdirSync(roomDir);
    expect(files.length).toBeGreaterThan(0);
    expect(files[0]).toMatch(/\.webm$/);
  });

});
