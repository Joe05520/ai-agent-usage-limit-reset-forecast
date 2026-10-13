function assessResetText(text){
 if(text.length>100000)return null;
 text=text.toLowerCase().replaceAll('’',"'");
 const f=Object.fromEntries(Object.entries(resetSemanticModel.features).map(([k,v])=>[k,new RegExp(v).test(text)]));
 if(!Object.entries(f).some(([k,v])=>k!=='reset'&&v))return null;
 let n=resetSemanticModel.tree,reasons=[];
 for(let i=0;i<16&&n.feature;i++){if(f[n.feature])reasons.push(n.feature);n=n[f[n.feature]?'yes':'no'];}
 const required={forecast:'future',poll:'poll',completed:'completed',accountReport:'completed',uncertain:'wish',regular:'regular',negative:'negative',irrelevant:'unrelated'};
 if(!f[required[n.label]]||(n.label==='regular'&&f.exception))return null;
 return {label:n.label,factor:resetSemanticModel.factors[n.label],reasons};
}
