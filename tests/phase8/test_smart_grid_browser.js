const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const BASE_URL = 'https://localhost:8443';
const PASSWORD = 'gridtestpassword';

test.describe('Smart Grid Recording Merging', () => {
  test('Creates a merged grid after users leave', async ({ browser }) => {
    test.setTimeout(45000); // Allow extra time for grid processing
    
    const context1 = await browser.newContext({ ignoreHTTPSErrors: true });
    const context2 = await browser.newContext({ ignoreHTTPSErrors: true });
    
    const page1 = await context1.newPage();
    const page2 = await context2.newPage();
    
    // Peer 1: Create room
    await page1.goto(BASE_URL);
    await page1.fill('#password', PASSWORD);
    await page1.click('#createBtn');
    
    // Wait for room ID
    await page1.waitForFunction(() => {
      const input = document.getElementById('roomId');
      return input && input.value && input.value.length === 36;
    }, { timeout: 10000 });
    
    const roomId = await page1.locator('#roomId').inputValue();
    console.log(`Room ID: ${roomId}`);
    
    // Peer 1: Actually join the room now
    await page1.click('#tabJoin');
    await page1.fill('#password', PASSWORD); // ensure password is filled
    await page1.click('#authActionBtn');

    // Wait for connection and start recording
    await page1.waitForFunction(() => {
      return document.getElementById('recordBtn').disabled === false;
    });
    await page1.click('#recordBtn');
    
    // Wait a bit to create an offset
    await page1.waitForTimeout(2000);
    
    // Peer 2: Join room
    await page2.goto(BASE_URL);
    await page2.fill('#roomId', roomId);
    await page2.fill('#password', PASSWORD);
    await page2.click('#joinBtn');
    
    // Wait for Peer 2 to connect and start recording
    await page2.waitForFunction(() => {
      return document.getElementById('recordBtn').disabled === false;
    });
    await page2.click('#recordBtn');
    
    // Both record for a short duration
    await page1.waitForTimeout(3000);
    
    // Peer 2 stops and leaves
    await page2.click('#recordBtn');
    await page2.click('#leaveBtn');
    
    // Peer 1 stops and leaves
    await page1.click('#recordBtn');
    await page1.click('#leaveBtn');
    
    console.log('Both peers left. Waiting 15 seconds for smart grid processing...');
    await page1.waitForTimeout(15000);
    
    // Verify recordings exist
    const recordingsDir = path.join(__dirname, '..', 'recordings', roomId);
    expect(fs.existsSync(recordingsDir)).toBeTruthy();
    
    const files = fs.readdirSync(recordingsDir);
    console.log('Files in recording dir:', files);
    
    // There should be 2 webm files + grid_merged.webm
    expect(files.includes('grid_merged.webm')).toBeTruthy();
    
    const gridFile = path.join(recordingsDir, 'grid_merged.webm');
    const stats = fs.statSync(gridFile);
    expect(stats.size).toBeGreaterThan(1000); // File shouldn't be empty
    
    // Use ffprobe to verify video and audio streams
    try {
      const ffprobeCmd = `ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${gridFile}"`;
      const vCodec = execSync(ffprobeCmd, { encoding: 'utf-8' }).trim();
      console.log('Video codec:', vCodec);
      expect(vCodec).toBe('vp9');
      
      const ffprobeAudio = `ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${gridFile}"`;
      const aCodec = execSync(ffprobeAudio, { encoding: 'utf-8' }).trim();
      console.log('Audio codec:', aCodec);
      expect(aCodec).toBe('opus');
    } catch (err) {
      console.error('ffprobe failed:', err.message);
      throw err;
    }
  });
});
