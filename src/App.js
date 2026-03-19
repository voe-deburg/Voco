import React from "react";
import "./index.css";
import Navbar from "../src/components/Navbar";
import Footer from "../src/components/Footer";
import Main from "../src/components/Main";


function App() {
  return (
    <>
    <Navbar/>
    <Main/>
    <Footer/>
    </>
 
  );
}

export default App;

// <div className="Navbar">
//   <h1>Ivor Gikonyo</h1>
//   <ul className="Navbar--links">
//     <li>
//       <a href="nyenyanyenya.com">Resume</a>
//     </li>
//     <li>
//       <a href="nyenyanyenya.com">Software solutions</a>
//     </li>
//     <li>
//       <a href="nyenyanyenya.com">Projects</a>
//     </li>
//     <li>
//       <a href="nyenyanyenya.com">About</a>
//     </li>
//     <li>
//       <a href="nyenyanyenya.com">contact</a>
//     </li>
//   </ul>
// </div>
