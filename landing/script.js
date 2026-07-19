/**
 * NekoLink Landing Page — Interactions
 * - Staggered entrance animations
 * - Beam fade-in with delay
 * - 3D tilt on product mockup
 */

document.addEventListener('DOMContentLoaded', () => {
  const beams = document.querySelectorAll('.beam');
  const animatedElements = document.querySelectorAll('[data-animate]');
  const tiltWrapper = document.querySelector('[data-tilt]');

  // 1. 内容进场动画 —— 通过 IntersectionObserver 让首屏立即触发，
  //    折叠以下的 section 进入视口时再触发
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('animate-in');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

    animatedElements.forEach(el => observer.observe(el));
  } else {
    // Fallback: 立即全部触发
    animatedElements.forEach(el => el.classList.add('animate-in'));
  }

  // 2. 光束延迟 0.5s 后淡入亮起
  setTimeout(() => {
    beams.forEach(beam => beam.classList.add('animate-in'));
  }, 500);

  // 3. 3D Tilt 交互
  if (tiltWrapper) {
    const mockup = tiltWrapper.querySelector('.mockup');
    if (!mockup) return;

    const maxRotateX = 8;   // 最大 X 轴旋转角度
    const maxRotateY = 8;   // 最大 Y 轴旋转角度
    const maxTranslateZ = 20; // 最大 Z 轴位移

    const handleMove = (e) => {
      const rect = tiltWrapper.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      // 鼠标相对于中心的归一化位置 (-1 到 1)
      const percentX = (e.clientX - centerX) / (rect.width / 2);
      const percentY = (e.clientY - centerY) / (rect.height / 2);

      // 计算旋转角度（Y 轴旋转由 X 方向控制，X 轴旋转由 Y 方向控制）
      const rotateY = percentX * maxRotateY;
      const rotateX = -percentY * maxRotateX;

      // 轻微的 Z 轴位移增加立体感
      const translateZ = Math.max(0, (1 - Math.abs(percentX)) * maxTranslateZ);

      mockup.style.transform = `rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateZ(${translateZ}px)`;
    };

    const handleLeave = () => {
      // 离开时平滑复位
      mockup.style.transition = 'transform 0.5s cubic-bezier(0.22, 1, 0.36, 1)';
      mockup.style.transform = 'rotateX(0deg) rotateY(0deg) translateZ(0px)';

      // 清除 transition 避免影响后续鼠标移动
      setTimeout(() => {
        mockup.style.transition = 'transform 0.15s ease-out';
      }, 500);
    };

    // 桌面端：鼠标移动
    tiltWrapper.addEventListener('mousemove', handleMove);
    tiltWrapper.addEventListener('mouseleave', handleLeave);

    // 移动端/触控：陀螺仪或触摸（可选，此处仅做简单触摸支持）
    tiltWrapper.addEventListener('touchmove', (e) => {
      if (e.touches.length === 1) {
        const touch = e.touches[0];
        handleMove(touch);
      }
    }, { passive: true });

    tiltWrapper.addEventListener('touchend', handleLeave);
  }
});
