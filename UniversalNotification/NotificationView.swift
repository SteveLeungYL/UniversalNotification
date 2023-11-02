//
//  NotificationView.swift
//  UniversalNotification
//
//  Created by Yu Liang on 11/2/23.
//

import SwiftUI

struct NotificationView: View {
    @State var appName = "Universal Notification"
    var body: some View {
        VStack(alignment: .center, content: {
            HStack {
                Text(appName).font(.system(size:50))
            }
        })
    }
    ;
}

#Preview {
    NotificationView()
}
