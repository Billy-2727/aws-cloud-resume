// fetch api data for the view function
const counter = document.querySelector(".view-counter");
async function updateCounter() {
    mode: 'no-cors'
    let response = await fetch("https://zrsqcovodn3lzhg5kirtjm6ziq0swedm.lambda-url.eu-west-2.on.aws/");
    let data = await response.json();
    counter.innerHTML = ` Views: ${data}`;
}

updateCounter();