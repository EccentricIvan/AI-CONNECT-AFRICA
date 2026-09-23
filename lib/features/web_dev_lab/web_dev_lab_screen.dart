import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/coding/code_lab.dart';
import '../../shared/coding/code_lab_session.dart';

/// Web Dev Lab: guided lessons -> edit the code -> RUN -> the real page.
///
/// Shares [CodeLabScaffold] with the App Dev Lab so the two labs stay one
/// product: the student writes the code, a browser engine paints exactly that
/// code, and the coding model is only ever reachable through Autocorrect.
class WebDevLabScreen extends ConsumerStatefulWidget {
  const WebDevLabScreen({super.key});

  @override
  ConsumerState<WebDevLabScreen> createState() => _WebDevLabScreenState();
}

class _WebDevLabScreenState extends ConsumerState<WebDevLabScreen> {
  @override
  Widget build(BuildContext context) {
    return const CodeLabScaffold(
      title: 'Web Dev Lab',
      icon: Icons.code,
      lessons: webLabLessons,
      sessionId: CodeLabSections.web,
    );
  }
}

// -- Lessons ------------------------------------------------------------------

const webLabLessons = <CodeLabLesson>[
  CodeLabLesson(
    title: 'Lesson 1: Your First Web Page',
    instruction:
        'Every web page starts with HTML tags. The <h1> tag creates a big heading '
        'and <p> creates a paragraph. Try changing the text inside the tags below, '
        'then tap RUN to see your page!',
    starterCode: '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>My Page</title></head>
<body>

  <h1>Hello World!</h1>
  <p>This is my first web page.</p>

</body>
</html>''',
    hint: 'Try adding another <p> paragraph below the first one.',
    challenge: 'Add a second heading using <h2> and another paragraph.',
  ),
  CodeLabLesson(
    title: 'Lesson 2: Adding Style with CSS',
    instruction:
        'CSS changes how your page looks — colors, fonts, spacing. '
        'CSS goes inside <style> tags in the <head>. '
        'Try changing the color value to "red" or "green" and tap RUN.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f0f4f8;
      padding: 20px;
    }
    h1 {
      color: #4F46E5;
    }
    p {
      color: #333;
      font-size: 18px;
    }
  </style>
</head>
<body>

  <h1>Styled Page</h1>
  <p>This text is styled with CSS!</p>

</body>
</html>''',
    hint: 'Try changing background-color to lightblue or #ffd700 (gold).',
    challenge: 'Add a border to the paragraph: border: 2px solid #4F46E5;',
  ),
  CodeLabLesson(
    title: 'Lesson 3: Links and Images',
    instruction:
        'Links use <a href="url">text</a> to connect pages. '
        'Images use <img src="url" alt="description">. '
        'Edit the link text and try adding another link below it.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial; padding: 20px; }
    a { color: #4F46E5; font-size: 18px; }
    img { max-width: 100%; border-radius: 12px; margin-top: 16px; }
  </style>
</head>
<body>

  <h1>Links and Images</h1>
  <p>Click the link below:</p>
  <a href="https://example.com">Visit Example.com</a>

  <p>Here is an image:</p>
  <img src="data:image/svg+xml;utf8,<svg xmlns=%27http://www.w3.org/2000/svg%27 width=%27400%27 height=%27200%27><rect width=%27400%27 height=%27200%27 fill=%27%234F46E5%27/><circle cx=%27320%27 cy=%2750%27 r=%2728%27 fill=%27%23FDE68A%27/><path d=%27M0 160 L110 95 L190 145 L280 80 L400 150 L400 200 L0 200 Z%27 fill=%27%2334D399%27/></svg>" alt="A drawing of hills at sunrise">

</body>
</html>''',
    hint: 'Add another link: <a href="https://google.com">Google</a>',
    challenge: 'Create a list of 3 links using <ul> and <li> tags.',
  ),
  CodeLabLesson(
    title: 'Lesson 4: Building a Card',
    instruction:
        'Cards are boxes with rounded corners and shadows — used everywhere in modern design. '
        'A <div> with CSS creates a card. Try changing the border-radius or box-shadow values.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      font-family: Arial;
      background: #f0f4f8;
      padding: 20px;
    }
    .card {
      background: white;
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
      max-width: 400px;
    }
    .card h2 { color: #4F46E5; margin-top: 0; }
    .card p { color: #555; line-height: 1.6; }
    .btn {
      background: #4F46E5;
      color: white;
      border: none;
      padding: 10px 24px;
      border-radius: 8px;
      font-size: 16px;
      cursor: pointer;
    }
  </style>
</head>
<body>

  <div class="card">
    <h2>My First Card</h2>
    <p>Cards are everywhere — apps, websites, social media. You just built one!</p>
    <button class="btn">Learn More</button>
  </div>

</body>
</html>''',
    hint: 'Try adding a second card below the first one.',
    challenge: 'Create a profile card with a name, description, and a colored border-left.',
  ),
  CodeLabLesson(
    title: 'Lesson 5: Interactive JavaScript',
    instruction:
        'JavaScript makes pages interactive. '
        'The code below changes the heading color when you click the button. '
        'Try changing what happens — maybe change the text instead of the color!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    h1 { color: #4F46E5; transition: color 0.3s; }
    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 12px 24px; border-radius: 8px;
      font-size: 16px; cursor: pointer; margin-top: 12px;
    }
    #counter { font-size: 48px; font-weight: bold; color: #4F46E5; }
  </style>
</head>
<body>

  <h1 id="title">Click the Button!</h1>
  <p id="counter">0</p>
  <button class="btn" onclick="count()">Click Me</button>

  <script>
    let clicks = 0;
    function count() {
      clicks++;
      document.getElementById('counter').textContent = clicks;
      if (clicks >= 10) {
        document.getElementById('title').textContent = 'You did it! 🎉';
      }
    }
  </script>

</body>
</html>''',
    hint: 'Try changing the message that appears at 10 clicks.',
    challenge: 'Add a reset button that sets the counter back to 0.',
  ),
  CodeLabLesson(
    title: 'Lesson 6: Forms and Input',
    instruction:
        'Forms collect user input. <input> creates text fields, <textarea> for multi-line, '
        '<select> for dropdowns. This form greets the user by name. '
        'Try adding another input field for their favorite subject!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    .form-card {
      background: white; border-radius: 16px;
      padding: 24px; max-width: 400px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    input, select {
      width: 100%; padding: 10px; margin: 8px 0 16px;
      border: 2px solid #ddd; border-radius: 8px;
      font-size: 16px; box-sizing: border-box;
    }
    input:focus { border-color: #4F46E5; outline: none; }
    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 12px 24px; border-radius: 8px;
      font-size: 16px; cursor: pointer; width: 100%;
    }
    #greeting { color: #4F46E5; font-size: 20px; margin-top: 16px; }
  </style>
</head>
<body>

  <div class="form-card">
    <h2>Welcome Form</h2>
    <label>Your Name:</label>
    <input type="text" id="nameInput" placeholder="Enter your name">

    <label>Your Age:</label>
    <select id="ageSelect">
      <option>Under 13</option>
      <option>13-17</option>
      <option>18-25</option>
      <option>Over 25</option>
    </select>

    <button class="btn" onclick="greet()">Say Hello</button>
    <p id="greeting"></p>
  </div>

  <script>
    function greet() {
      const name = document.getElementById('nameInput').value;
      const age = document.getElementById('ageSelect').value;
      if (name) {
        document.getElementById('greeting').textContent =
          'Hello, ' + name + '! Age group: ' + age;
      } else {
        document.getElementById('greeting').textContent = 'Please enter your name!';
      }
    }
  </script>

</body>
</html>''',
    hint: 'Add a <textarea> for a short bio after the age selector.',
    challenge: 'Validate the form — show an error if name is empty when submitted.',
  ),
  CodeLabLesson(
    title: 'Lesson 7: Flexbox Layout',
    instruction:
        'Flexbox arranges items in rows or columns easily. '
        'display: flex on a container, then use justify-content and align-items. '
        'Try changing "row" to "column" and see what happens!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f4f8; }
    .flex-container {
      display: flex;
      flex-direction: row;
      gap: 16px;
      flex-wrap: wrap;
    }
    .box {
      background: #4F46E5;
      color: white;
      padding: 24px;
      border-radius: 12px;
      text-align: center;
      font-size: 18px;
      font-weight: bold;
      flex: 1;
      min-width: 100px;
    }
    .box:nth-child(2) { background: #0EA5E9; }
    .box:nth-child(3) { background: #10B981; }
    .box:nth-child(4) { background: #F59E0B; }
  </style>
</head>
<body>

  <h1>Flexbox Layout</h1>
  <div class="flex-container">
    <div class="box">Box 1</div>
    <div class="box">Box 2</div>
    <div class="box">Box 3</div>
    <div class="box">Box 4</div>
  </div>

</body>
</html>''',
    hint: 'Try justify-content: center; or space-between; on the container.',
    challenge: 'Create a navigation bar using flexbox with 4 links in a row.',
  ),
  CodeLabLesson(
    title: 'Lesson 8: Build a Mini Website',
    instruction:
        'Combine everything you learned! This is a complete mini website with '
        'a header, navigation, content cards, and footer. '
        'Customize it — change the name, colors, and content to make it yours!',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; box-sizing: border-box; }
    body { font-family: Arial, sans-serif; background: #f0f4f8; color: #1a202c; }

    header {
      background: #4F46E5; color: white;
      padding: 20px; text-align: center;
    }
    nav {
      background: #3730A3; padding: 10px;
      display: flex; justify-content: center; gap: 20px;
    }
    nav a { color: white; text-decoration: none; font-weight: bold; }
    nav a:hover { text-decoration: underline; }

    .content { padding: 20px; max-width: 600px; margin: auto; }

    .card {
      background: white; border-radius: 12px; padding: 20px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 16px;
    }
    .card h3 { color: #4F46E5; }

    footer {
      background: #1E293B; color: #94A3B8;
      text-align: center; padding: 16px; margin-top: 32px;
    }

    .btn {
      background: #4F46E5; color: white; border: none;
      padding: 10px 20px; border-radius: 8px; cursor: pointer;
    }
  </style>
</head>
<body>

  <header>
    <h1>My Website</h1>
    <p>Built with HTML, CSS & JS</p>
  </header>

  <nav>
    <a href="#home">Home</a>
    <a href="#about">About</a>
    <a href="#contact">Contact</a>
  </nav>

  <div class="content">
    <div class="card">
      <h3>Welcome!</h3>
      <p>This is a complete mini website. You built this!</p>
      <button class="btn" onclick="alert('You clicked!')">Click Me</button>
    </div>

    <div class="card">
      <h3>About Me</h3>
      <p>I am learning web development with AI Connect Africa.
         I can now build web pages with HTML, style them with CSS,
         and make them interactive with JavaScript.</p>
    </div>

    <div class="card">
      <h3>My Skills</h3>
      <ul>
        <li>HTML — Structure</li>
        <li>CSS — Styling</li>
        <li>JavaScript — Interactivity</li>
      </ul>
    </div>
  </div>

  <footer>
    <p>&copy; 2024 My Website — Built with AI Connect Africa</p>
  </footer>

</body>
</html>''',
    hint: 'Change the header color and add your real name.',
    challenge: 'Add a dark mode toggle button using JavaScript that switches background and text colors!',
  ),
];

// ── Screen ───────────────────────────────────────────────────────────────────
