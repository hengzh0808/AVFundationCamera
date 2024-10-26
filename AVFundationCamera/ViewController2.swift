//
//  ViewController2.swift
//  AVFundationCamera
//
//  Created by hengzh on 2024/10/11.
//

import UIKit

class ViewController2: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let alert = UIAlertController(title: "镜头模式", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "广角", style: .default) { _ in
            
        })
        alert.addAction(UIAlertAction(title: "超广角", style: .default) { _ in
            
        })
        alert.addAction(UIAlertAction(title: "长焦", style: .default) { _ in
            
        })
        alert.addAction(UIAlertAction(title: "三摄", style: .default) { _ in
            
        })
        UIApplication.shared.delegate?.window??.rootViewController?.present(alert, animated: true)
        // Do any additional setup after loading the view.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
