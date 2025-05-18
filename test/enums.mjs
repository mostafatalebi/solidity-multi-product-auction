  

function Enum(...options) {
    var obj = {}
    options.forEach(function(v, k) {
        obj[v] = BigInt(String(k));
    });
    return obj
}

const ActivationType = Enum("Manual", "Temporal");
const StartStatus = Enum("NotStarted", "Started", "Closed");
const EntityType = Enum("Owner", "Bid", "Product", "Bidder");

export { ActivationType, StartStatus, EntityType }
  