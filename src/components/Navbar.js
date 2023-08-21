import React from "react";
import "../index.css";

export default function Navbar() {
  return (
    <div className="Navbar">
      <h1>Ivor Gikonyo</h1>
      <ul className="Navbar--links">
        <li>
          <a href="nyenyanyenya.com">Resume</a>
        </li>
        <li>
          <a href="nyenyanyenya.com">Software solutions</a>
        </li>
        <li>
          <a href="nyenyanyenya.com">Projects</a>
        </li>
        <li>
          <a href="nyenyanyenya.com">About</a>
        </li>
        <li>
          <a href="nyenyanyenya.com">contact</a>
        </li>
      </ul>
    </div>
  );
}
